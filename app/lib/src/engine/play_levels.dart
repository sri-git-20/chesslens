import 'engine_service.dart';

/// One playing level of "Play vs engine".
class PlayLevel {
  const PlayLevel._(this.number, this.label, this.thinkTimeMs, this._skillLevel, this._eloFraction);

  /// 1 to 8.
  final int number;
  final String label;

  /// Fixed think time per move.
  final int thinkTimeMs;

  final int? _skillLevel;
  final double? _eloFraction;

  /// Levels 1 and 2 use Stockfish's Skill Level, which plays weaker than the
  /// lowest UCI_Elo. Levels 3 to 8 spread over the UCI_Elo range.
  static const List<PlayLevel> levels = [
    PlayLevel._(1, 'Level 1', 150, 0, null),
    PlayLevel._(2, 'Level 2', 250, 5, null),
    PlayLevel._(3, 'Level 3', 400, null, 0.0),
    PlayLevel._(4, 'Level 4', 600, null, 0.15),
    PlayLevel._(5, 'Level 5', 800, null, 0.3),
    PlayLevel._(6, 'Level 6', 1200, null, 0.5),
    PlayLevel._(7, 'Level 7', 1800, null, 0.7),
    PlayLevel._(8, 'Level 8', 2500, null, 0.9),
  ];

  /// Full strength has no level number; it uses [fullStrength].
  static const PlayLevel fullStrength = PlayLevel._(9, 'Full strength', 3000, null, null);

  /// The engine strength for this level given the engine's UCI_Elo [range].
  EngineStrength strength(EloRange range) {
    if (_skillLevel != null) return EngineStrength.skill(_skillLevel);
    final fraction = _eloFraction;
    if (fraction == null) return const EngineStrength.full();
    final raw = range.min + (range.max - range.min) * fraction;
    final rounded = (raw / 10).round() * 10;
    final elo = rounded < range.min ? range.min : (rounded > range.max ? range.max : rounded);
    return EngineStrength.elo(elo);
  }

  /// A short description such as "about 1620 Elo".
  String describe(EloRange range) {
    final value = strength(range);
    if (value.elo != null) return 'about ${value.elo} Elo';
    if (value.isFull) return 'no limit';
    return 'beginner';
  }
}
