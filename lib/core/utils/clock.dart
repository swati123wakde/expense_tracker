/// Injectable time source so calculations, sync and recurrence are testable.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();

  int nowMs() => now().millisecondsSinceEpoch;
}

/// A clock that returns a fixed (but adjustable) instant. Used in tests.
class FixedClock extends Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration d) => current = current.add(d);
}
