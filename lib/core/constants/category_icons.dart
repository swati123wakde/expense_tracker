import 'package:flutter/material.dart';

/// Icons are persisted by key (not code point) so they survive tree-shaking
/// and stay stable across devices and backups.
class AppIcons {
  AppIcons._();

  static const Map<String, IconData> all = {
    'food': Icons.restaurant,
    'travel': Icons.flight_takeoff,
    'shopping': Icons.shopping_bag,
    'bills': Icons.receipt_long,
    'rent': Icons.home,
    'entertainment': Icons.movie,
    'health': Icons.local_hospital,
    'education': Icons.school,
    'subscription': Icons.subscriptions,
    'other': Icons.category,
    'salary': Icons.work,
    'freelance': Icons.computer,
    'business': Icons.business_center,
    'investment': Icons.trending_up,
    'gift': Icons.card_giftcard,
    'cash': Icons.payments,
    'bank': Icons.account_balance,
    'credit_card': Icons.credit_card,
    'wallet': Icons.account_balance_wallet,
    'savings': Icons.savings,
    'car': Icons.directions_car,
    'pets': Icons.pets,
    'gym': Icons.fitness_center,
    'coffee': Icons.local_cafe,
    'phone': Icons.phone_android,
    'games': Icons.sports_esports,
    'kids': Icons.child_care,
    'groceries': Icons.local_grocery_store,
    'internet': Icons.wifi,
    'electricity': Icons.bolt,
    'water': Icons.water_drop,
    'laptop': Icons.laptop_mac,
    'vacation': Icons.beach_access,
    'bike': Icons.directions_bike,
    'house': Icons.house,
    'diamond': Icons.diamond,
    'money': Icons.attach_money,
    'star': Icons.star,
    'flag': Icons.flag,
  };

  static IconData of(String? key) => all[key] ?? Icons.category;
}

/// A pleasant palette for categories, accounts and goals.
class AppPalette {
  AppPalette._();

  static const List<int> colors = [
    0xFFEF6C00, 0xFF1E88E5, 0xFF8E24AA, 0xFFE53935, 0xFF6D4C41, //
    0xFFD81B60, 0xFF43A047, 0xFF3949AB, 0xFF00897B, 0xFF757575,
    0xFF2E7D32, 0xFF00ACC1, 0xFF5E35B1, 0xFFF9A825, 0xFFC0CA33,
  ];
}
