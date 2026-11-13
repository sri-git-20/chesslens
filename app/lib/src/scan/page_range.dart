/// The result of reading a range such as `3-7, 9`.
class RangeParse {
  const RangeParse.ok(Set<int> this.numbers) : error = null;
  const RangeParse.error(String this.error) : numbers = null;

  final Set<int>? numbers;
  final String? error;

  bool get isValid => error == null;
}

/// Parses numbers and ranges such as `3-7, 9` into a set. Numbers must be in
/// `1..max`.
RangeParse parseRange(String text, int max) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const RangeParse.error('Type numbers like 3-7, 9.');
  }
  final result = <int>{};
  final normalized = trimmed.replaceAll(RegExp(r'\s*[-\u2013]\s*'), '-');
  for (final part in normalized.split(RegExp(r'[,;\s]+'))) {
    if (part.isEmpty) continue;
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(part);
    if (match == null) {
      return const RangeParse.error('Type numbers like 3-7, 9.');
    }
    // tryParse: a very long number is not an int and must not throw.
    final a = int.tryParse(match.group(1)!);
    final b = match.group(2) == null ? a : int.tryParse(match.group(2)!);
    if (a == null || b == null) {
      return RangeParse.error('Numbers go from 1 to $max.');
    }
    if (a > b) {
      return RangeParse.error('"$part" goes backwards.');
    }
    if (a < 1 || b > max) {
      return RangeParse.error('Numbers go from 1 to $max.');
    }
    for (var n = a; n <= b; n++) {
      result.add(n);
    }
  }
  if (result.isEmpty) {
    return const RangeParse.error('Type numbers like 3-7, 9.');
  }
  return RangeParse.ok(result);
}
