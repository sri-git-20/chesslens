import 'package:dartchess/dartchess.dart';

import '../analysis/move_tree.dart';
import '../collections/models.dart';

/// Escapes a PGN tag value: backslash and double quote.
String pgnEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(RegExp(r'[\r\n]+'), ' ');

/// The SAN moves of the main line, starting at [root].
List<String> mainlineSan(MoveNode root) {
  final moves = <String>[];
  var node = root;
  while (node.children.isNotEmpty) {
    node = node.children.first;
    final san = node.san;
    if (san != null) moves.add(san);
  }
  return moves;
}

/// Move text such as `1. e4 e5 2. Nf3 *`. Starts with `12...` when [turn] is
/// black. Lines are wrapped at 80 characters.
String pgnMovetext({
  required List<String> sanMoves,
  Side turn = Side.white,
  int fullmoves = 1,
  String result = '*',
}) {
  final tokens = <String>[];
  var number = fullmoves;
  var side = turn;
  var first = true;
  for (final san in sanMoves) {
    if (side == Side.white) {
      tokens.add('$number.');
    } else if (first) {
      tokens.add('$number...');
    }
    tokens.add(san);
    if (side == Side.black) number++;
    side = side.opposite;
    first = false;
  }
  tokens.add(result);

  final lines = <String>[];
  var line = '';
  for (final token in tokens) {
    if (line.isEmpty) {
      line = token;
    } else if (line.length + 1 + token.length > 80) {
      lines.add(line);
      line = token;
    } else {
      line = '$line $token';
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines.join('\n');
}

/// One PGN game that starts from [fen] (a full FEN) and plays [sanMoves].
///
/// Writes the seven tag roster, then `SetUp`, `FEN` and `Annotator`. Extra
/// [headers] replace the defaults of the same name.
String buildPgn({
  required String fen,
  List<String> sanMoves = const [],
  Map<String, String> headers = const {},
  String result = '*',
}) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  final turn = parts.length > 1 && parts[1] == 'b' ? Side.black : Side.white;
  final fullmoves = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;

  final tags = <String, String>{
    'Event': 'ChessLens position',
    'Site': '?',
    'Date': '????.??.??',
    'Round': '-',
    'White': '?',
    'Black': '?',
    'Result': result,
    ...headers,
    'SetUp': '1',
    'FEN': fen.trim(),
    'Annotator': 'ChessLens',
  };
  final buffer = StringBuffer();
  tags.forEach((name, value) => buffer.writeln('[$name "${pgnEscape(value)}"]'));
  buffer
    ..writeln()
    ..writeln(pgnMovetext(sanMoves: sanMoves, turn: turn, fullmoves: fullmoves, result: result));
  return buffer.toString();
}

/// The PGN of the analysis tree: its root position and the main line.
String pgnFromTree(MoveTree tree) => buildPgn(
      fen: tree.root.position.fen,
      sanMoves: mainlineSan(tree.root),
    );

/// A whole collection: one game per puzzle, numbered from 1 in the order
/// given, separated by blank lines.
String buildCollectionPgn(String collectionName, List<Puzzle> puzzles) {
  final games = <String>[];
  for (var index = 0; index < puzzles.length; index++) {
    games.add(
      buildPgn(
        fen: puzzles[index].fen,
        headers: {'Event': collectionName, 'Round': '${index + 1}'},
      ),
    );
  }
  return games.join('\n');
}

/// A safe file name for [name]: letters, digits, dash and underscore.
String safeFileName(String name, {String fallback = 'collection'}) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

/// The Lichess analysis board for [fen].
String lichessAnalysisUrl(String fen) =>
    'https://lichess.org/analysis/standard/${fen.trim().replaceAll(RegExp(r'\s+'), '_')}';
