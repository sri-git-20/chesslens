import 'package:chessground/chessground.dart';

/// Board colour themes offered in Settings. All are plain colours, so they
/// need no extra assets and look the same in light, dark and true-black mode.
enum BoardTheme {
  green('Green', ChessboardColorScheme.green),
  brown('Brown', ChessboardColorScheme.brown),
  blue('Blue', ChessboardColorScheme.blue),
  ic('Sand', ChessboardColorScheme.ic);

  const BoardTheme(this.label, this.colors);

  final String label;
  final ChessboardColorScheme colors;

  static const BoardTheme defaultTheme = BoardTheme.green;

  static BoardTheme fromName(String? name) => BoardTheme.values.firstWhere(
        (theme) => theme.name == name,
        orElse: () => defaultTheme,
      );
}

/// The piece set used when nothing is stored.
const PieceSet defaultPieceSet = PieceSet.cburnett;

PieceSet pieceSetFromName(String? name) => PieceSet.values.firstWhere(
      (set) => set.name == name,
      orElse: () => defaultPieceSet,
    );
