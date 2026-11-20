# Expense Manager — offline-first Flutter app

A personal finance app that works completely offline. Every read and write goes to an **encrypted local SQLite database**. When the device is online, a background **sync engine** pushes your changes to Supabase and pulls changes from your other devices, merging them **field by field**.

> **Offline-first in one sentence:** the UI only ever reads the local database, and the cloud is just one more consumer of it.

---

## Contents

1. [Features](#features)
2. [Screenshots](#screenshots)
3. [Architecture](#architecture)
4. [Database design](#database-design)
5. [Local database setup (encryption)](#local-database-setup-encryption)
6. [Cloud setup (Supabase)](#cloud-setup-supabase)
7. [Sync strategy](#sync-strategy)
8. [Conflict resolution strategy](#conflict-resolution-strategy)
9. [Installation](#installation)
10. [Testing](#testing)
11. [Performance (10k transactions)](#performance-10k-transactions)
12. [Known limitations](#known-limitations)

---

## Features

| Area | What's implemented |
|---|---|
| Dashboard | Total balance (= total income − total expenses), total income, total expenses, this month's in/out, monthly budget with remaining and % used, budget warning, smart insights carousel, 6-month income-vs-expense bar chart, account balances strip, 8 most recent transactions, quick actions |
| Transactions | Add and edit with amount, type, category, account, note, date (defaults to today), time, optional receipt image, and a recurring toggle. Validation on every field. |
| History | Shows the category icon, the category, the note, the date and time, the account, a signed and coloured amount, and an income/expense badge. Filters can be combined: type, categories, accounts, date presets, a single date, a custom date range, an amount range and favourites. Search matches the note, the category or an exact amount. The list loads with keyset pagination. |
| Edit & delete | Swipe right to edit and swipe left to delete, with Undo. The details sheet deletes with a confirmation dialog. All views refresh through the change bus. |
| Analytics | Week / Month / 3 Months / Year: income, expenses, net savings, savings rate, average daily spend, category donut + ranked list, grouped income-vs-expense bars, spending trend line (daily/weekly/monthly granularity) |
| Smart insights | Computed from local data: week-over-week and month-over-month change (both compare the same number of elapsed days), top category with its share, budget usage, average daily spend, end-of-month projection and savings rate |
| Budgets | Monthly budget with a progress bar and warnings at 50%, 75%, 90% and 100%, plus an "exceeded by" message. Category budgets have their own progress. |
| Accounts | Cash, Bank, Credit Card, Wallet and Savings accounts. Each has a balance, and the combined balance is shown too. An opening balance is recorded as an income transaction. Accounts can be archived; an account can only be deleted if it has no transactions. Multi-currency is supported. |
| Recurring | Daily / weekly / monthly / yearly rules; due occurrences are materialised on launch/resume with **deterministic ids** (no duplicates across devices); monthly cost summary (subscription tracker) |
| Goals | Each goal has a name, a target, the amount saved, a target date, an icon and a colour. The screen shows progress, adds or withdraws money, and works out the monthly saving needed to hit the date. |
| Themes | Light / Dark / System, persisted locally, animated switch |
| Backup | JSON export/import (`version`, `transactions`, `categories`, `accounts`, `budgets`, `goals`, `recurring`, `settings`). The whole file is validated, including references between records, before anything is written. The import then runs in a single SQL transaction. |
| CSV | `Date,Type,Category,Account,Amount,Note` export of the current filter (e.g. July + Expenses + Food), streamed in pages, formula-injection safe |
| Sync | Supabase upsert/pull with soft deletes, per-table cursors, field-level 3-way merge, retry with exponential backoff, status chip (`✓ Synced`, `↻ Syncing...`, `☁ 4 changes waiting`, `⚠ Sync failed`, `Offline • 3 changes will sync later`) |
| Auth | Email/password sign-up/sign-in, logout (warns about unsynced changes, then wipes local data), **guest/local-only mode** (bonus); RLS isolates users |
| Custom categories | Create a category with a name, an icon, a type and a colour. Categories can be edited and archived; archived ones still resolve in old transactions. |
| Notifications | Budget alerts fire once per threshold per month, and only from 75% upwards (50% is shown in the app only). A "due tomorrow" reminder fires for recurring expenses. Both can be turned off. |
| Security | SQLCipher-encrypted DB, key in Android Keystore / iOS Keychain; optional PIN (salted, iterated SHA-256) + biometrics; lockout after 5 wrong PINs; locks after 30 s in background; app-switcher privacy cover; nothing financial is built while locked |
| Settings | All items listed in the brief, plus "Generate 10,000 demo transactions" |

Bonus items done: guest mode, receipt images, favourites, subscription tracker (monthly commitment), quick-add actions, encrypted DB, multi-currency.

## Screenshots

The screenshots in `docs/screenshots/` should be captured from a device build (`flutter run`). The repository does not include generated images. Recommended set: dashboard (light/dark), add transaction, history with filters, analytics, budgets, sync status offline.

## Architecture

```
lib/
├── app/            composition root (AppDependencies), app widget, config
├── core/
│   ├── constants/  default categories/accounts, icon & colour palette
│   ├── finance/    PURE calculators: balance, budget, analytics, insights, recurrence, currency
│   ├── services/   connectivity, notifications, alerts, app lock, secure store, exchange rates, change bus
│   ├── theme/      Material 3 theme + FinanceColors extension
│   └── utils/      money (minor units), dates, clock, ids
├── data/
│   ├── local/      AppDatabase (schema/migrations), SyncableDao, query builder, SQLCipher opener
│   ├── remote/     RemoteDataSource (Supabase + in-memory), AuthService
│   ├── models/     entities, filter, settings
│   └── repositories/ transaction, account, category, budget, goal, recurring, settings, backup
├── providers/      ChangeNotifiers (one per feature) – no widget logic, no SQL
├── features/       auth, dashboard, transactions, analytics, budgets, accounts, goals,
│                   categories, recurring, settings, lock, shell, common widgets
├── sync/           sync_service.dart, sync_queue.dart, conflict_resolver.dart
└── main.dart
```

**Data flow:** `Widget → Provider → Repository → Local DB ↕ Sync Engine ↕ Cloud`

* Widgets call provider methods and render provider state. They never touch SQL or business rules.
* Repositories are the only code that writes SQL. Every write to a synced table goes through `SyncableDao`, which stamps `updated_at`, picks the right `sync_status` and soft-deletes. That bookkeeping can't be skipped.
* After every write, repositories publish on a `DataChangeBus`. Providers subscribe and reload. Several changes in the same event-loop turn are coalesced into one reload. The sync engine also listens and schedules a debounced upload. Sync merges publish on the same bus, so the UI updates when cloud data arrives.
* All maths (balances, budgets, analytics, insights, recurrence) lives in pure functions in `core/finance`, which makes it easy to unit-test.
* `AppDependencies` is the single composition root. Tests swap in the database, clock, cloud, connectivity, notifications and biometrics.

### Startup (offline-first)

```
main() → open encrypted DB (key from keystore) → load settings → runApp
       → providers read local DB → dashboard renders
       → post-frame: process due recurring rules → SyncService.start()
            → check connectivity → (online) pull changes since cursor → merge → push pending
            → publish changes → providers refresh
```
Supabase initialisation only restores a locally persisted session and is capped by a timeout, so startup can't hang on the cloud. No screen waits for the network.

## Database design

All money is stored as **integer minor units** (`amount_minor`, cents) to avoid floating-point errors. Timestamps are epoch milliseconds.

Every synced table has: `id`, `user_id`, `created_at`, `updated_at`, `deleted_at`, `sync_status`, `sync_base`.

| Table | Content columns |
|---|---|
| `accounts` | name, type, currency, icon, color, archived |
| `categories` | name, type, icon, color, is_custom, archived, sort_order |
| `transactions` | type, amount_minor, category_id, account_id, note, occurred_at, recurring_rule_id, is_favorite, *(local-only: attachment_path)* |
| `budgets` | category_id (NULL = overall monthly budget), amount_minor |
| `goals` | name, target_minor, saved_minor, target_date, icon, color |
| `recurring_rules` | type, amount_minor, category_id, account_id, note, frequency, start_at, end_at, occurrences_generated, next_due_at, active |
| `settings` | key/value (device-local: theme, currency, lock flags, sync cursors, alert bookkeeping) |
| `exchange_rates` | currency, rate_per_usd, fetched_at (cached for offline conversion) |

* `sync_status` ∈ `synced | pendingCreate | pendingUpdate | pendingDelete | failed`.
* `sync_base` stores a JSON snapshot of the record as last agreed with the cloud. It is the common ancestor for the three-way merge.
* Indexes: `(deleted_at, occurred_at DESC, id DESC)` for paginated history; `category_id`, `account_id`; `sync_status` on each synced table.
* Deterministic ids make concurrent creation on two devices converge on one record: `cat_food` and `acc_cash` for seed data, `budget_overall` and `budget_cat_<id>` for budgets, and `rec_<rule>_<n>` for recurring occurrences.

## Local database setup (encryption)

* The local store is `sqflite_sqlcipher`, which is SQLite with SQLCipher AES-256. The whole database file is encrypted.
* On first launch a random 256-bit passphrase is generated with `Random.secure()`. It is stored with `flutter_secure_storage`, which uses the Android Keystore with EncryptedSharedPreferences, or the iOS Keychain. It is never written to disk in plain text or into the code.
* `android:allowBackup="false"` keeps the database out of cloud backups.
* Schema versioning lives in `AppDatabase.migrate`, which runs forward-only migrations.
* Tests use `sqflite_common_ffi` with the same schema and SQL, but without encryption (see limitations).

## Cloud setup (Supabase)

1. Create a Supabase project. Under **Authentication → Providers**, enable Email.
2. Open the **SQL editor** and run [`supabase/schema.sql`](supabase/schema.sql). It creates six tables with:
   * a primary key on `(user_id, id)`
   * `server_updated_at`, set by a trigger with `clock_timestamp()` and used as the pull cursor
   * **Row Level Security**: select, insert and update require `auth.uid() = user_id`. There is no delete policy, because only soft deletes are allowed.
3. Copy the project URL and the anon key, then run:
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
               --dart-define=SUPABASE_ANON_KEY=<anon-key>
   ```
   Without these defines the app runs in **local-only mode**: no login and no sync, and everything else works.
4. For CI release builds, add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as repository secrets.

## Sync strategy

**Outbound queue.** The queue is implicit: every row whose `sync_status ≠ synced` is pending. Because the queue *is* the data, it can't drift out of step with it and it survives restarts. `SyncQueue` counts and batches these rows across tables.

**A sync run** (`SyncService._run`) works like this:

1. It bails out if sync is disabled (guest mode or no backend) or the device is offline. Those cases only update the status.
2. **Pull**, per table, with parents first (accounts → categories → budgets → goals → recurring → transactions). It fetches rows where `server_updated_at > cursor − 5 s`, page by page (500 per page). The 5-second overlap re-reads rows that commit late from concurrent writers. Re-applying a row is idempotent.
   * If the local row is missing or already `synced`, the cloud version is written and becomes the new `sync_base`. An unchanged echo of our own upload is skipped.
   * If the local row has pending edits, it goes through a **three-way merge** (next section). If the merged result differs from the cloud version, the row stays pending so the merge result gets uploaded.
   * Each table's cursor (`sync_cursor_<table>`) advances to the highest server timestamp seen. Only rows changed since the last sync are downloaded, never the whole database.
3. **Push** pending rows in batches of 200 with `upsert(onConflict: 'user_id,id')`. Each row is marked `synced` with `UPDATE … WHERE id = ? AND updated_at = ?`. A row edited while its upload was in flight therefore stays pending for the next run.
4. Store `last_sync_at` and publish the tables that changed, so the UI refreshes.

**Triggers:** the first frame after launch, connectivity coming back, any local change (debounced 2 s), the app resuming, every 5 minutes, and tapping the status chip or "Sync now". Concurrent requests coalesce into one follow-up run.

**Failures** never block the user. Rows whose upload failed are marked `failed`, and they are retried on the next run with exponential backoff (15 s → 8 min). An expired session shows a "sign in again" status.

**Deletion.** Deletes are soft. `deleted_at` is set and `sync_status` becomes `pendingDelete`. The tombstone is uploaded like any other change, so other devices remove the record and it never comes back on a later pull. All queries filter on `deleted_at IS NULL`.

**Logout** wipes the local database after a warning that names how many changes haven't synced yet. A different account on the same device therefore never sees the previous user's rows. Guest data is attached (`user_id` assigned) to the account the user signs in with.

## Conflict resolution strategy

Implemented in [`lib/sync/conflict_resolver.dart`](lib/sync/conflict_resolver.dart) and tested in `test/unit/conflict_resolver_test.dart` and `test/unit/sync_service_test.dart`.

**Field-level three-way merge.** For a record edited locally while the cloud copy also changed, every content field is compared against `sync_base`, the version both sides last agreed on:

| Local changed? | Cloud changed? | Result |
|---|---|---|
| no | no | unchanged |
| **yes** | no | local value |
| no | **yes** | cloud value |
| yes | yes (same value) | that value |
| yes | yes (different) | **Last-Write-Wins** by record `updated_at` |

* *Device A changes the note while Device B changes the amount:* both changes survive. Each device takes the other's field, A uploads the merged record, and B pulls it.
* *Device A sets Food $20 → $25 while Device B sets it → $30:* both changed `amount_minor`, so the later `updated_at` wins. This is the only case where a value is discarded.
* **Deterministic tie-break.** When the timestamps are equal, the higher value wins, compared as a string. Every device therefore reaches the same result whichever side it calls "local".
* **Delete vs edit.** `deleted_at` is merged like any other field, so a delete on one device survives a concurrent edit of other fields on another device. In effect, delete wins.
* **No base** happens when two devices create the same deterministic id, such as seeded categories or a recurring occurrence. Differing fields use LWW, and the seed timestamps of 0 mean real user edits always win.
* Metadata: `created_at` takes the earliest value and `updated_at` takes the latest.

## Installation

```bash
git clone <repo> && cd expense_manager
flutter create --platforms=android,ios --org com.example --project-name expense_manager .  # generates missing platform files only
flutter pub get
flutter run                                    # local-only
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build apk --release                    # build/app/outputs/flutter-apk/app-release.apk
```

Requirements are Flutter stable (3.27 or later) and Android minSdk 23. The Android project is committed and set up for SQLCipher, local_auth (`FlutterFragmentActivity`) and notification desugaring. iOS files come from `flutter create`. Add `NSFaceIDUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.

## Testing

```bash
flutter test                         # unit + widget + headless integration (needs libsqlite3 on Linux)
flutter test integration_test -d <device>   # on-device UI flows with the real SQLCipher DB
```

| Suite | File | Covers |
|---|---|---|
| Unit | `test/unit/calculations_test.dart` | money parsing and formatting, balance (incl. multi-currency), budget thresholds and messages, analytics totals and buckets, recurrence maths |
| Unit | `test/unit/insights_engine_test.dart` | every insight type, computed from data |
| Unit | `test/unit/conflict_resolver_test.dart` | field-level merge, LWW, deterministic ties, delete vs edit, no-base merge |
| Unit | `test/unit/transaction_query_builder_test.dart` | combinable filters, search, LIKE escaping, keyset SQL |
| Unit | `test/unit/repository_test.dart` | CRUD and sync status transitions, soft delete with undo, filters on a real DB, 10k-row pagination, aggregates, budgets, goals, recurring idempotency |
| Unit | `test/unit/sync_service_test.dart` | push, incremental pull, tombstones, two-device field merge, same-field LWW, failure and retry, user isolation, offline status |
| Unit | `test/unit/backup_and_services_test.dart` | JSON round trip, rejecting an invalid backup with no DB changes, CSV format and filters, PIN hashing, alert de-duplication |
| Widget | `test/widget/app_widgets_test.dart` | dashboard, add transaction (validation and save), filters and search, theme switching and persistence, budget warnings |
| Integration (headless) | `test/integration/offline_sync_flow_test.dart` | Create → View → Edit → Delete; Offline → Create/Edit/Delete → **Restart** → still exists → Online → Sync → Cloud contains it |
| Integration (device) | `integration_test/app_flow_test.dart` | the same flows driven through the real UI (swipes, undo, restart) |

CI (`.github/workflows/ci.yml`) runs `flutter analyze` and `flutter test` on every push and builds a release APK, which it uploads as the `expense-manager-release-apk` artifact.

### Manual offline test (section 29)

1. Turn on airplane mode and open the app. The dashboard renders immediately from the local DB, and the chip shows `Offline`.
2. Add a transaction, edit it and swipe-delete another one. The chip shows `Offline • 3 changes will sync later`.
3. Kill the app and reopen it. All the changes are still there, because they were persisted in SQLite before the UI updated.
4. Turn airplane mode off. The connectivity listener starts a sync, the chip moves through `↻ Syncing...` to `✓ Synced`, and the rows (including the tombstone) appear in Supabase.

## Performance (10k transactions)

* **Settings → Generate 10,000 demo transactions** inserts them in a single SQL transaction using batches of 1,000.
* History uses **keyset pagination** (`WHERE (occurred_at, id) < cursor ORDER BY occurred_at DESC, id DESC LIMIT 40`) over a covering index. Each page costs O(page) at any depth, with no OFFSET scans. `ListView.builder` only builds visible rows.
* Dashboard, analytics and budgets use **one grouped SQL aggregate** per screen (per day, type, category and currency) instead of loading transactions. The Dart calculators then work on a few hundred aggregate rows.
* CSV export streams pages of 500 rows.
* Provider reloads are coalesced per event-loop turn, and widgets rebuild only for the providers they watch.
* `repository_test.dart` paginates all 10,000 rows and asserts there are no duplicates or gaps.

## Known limitations

* **Not compiled in the authoring environment.** This code was written without access to a Flutter SDK. The GitHub Actions workflow is the first place `flutter analyze`, `flutter test` and the APK build run. Expect to fix a few small API mismatches on the first run.
* Tests use unencrypted SQLite via FFI. Encryption is exercised only in the on-device integration tests and in the app.
* Multi-currency assumes 2 decimal places for every currency. Rates come from open.er-api.com and are cached for 12 h, with bundled approximate fallbacks until the first fetch.
* Receipt images are stored on the device only. The path is a local-only column and is not synced.
* Reminders and recurring generation run when the app opens or resumes. There is no OS background job, so a notification can be late if the app isn't opened.
* There is a small race window: if another device writes the same record between our pull and our push in one run, our push wins at record level. The next run on the other device re-merges against the new base.
* Google Sign-In, the home-screen widget and per-field timestamps are not implemented.
#   e x p e n s e _ t r a c k e r  
 