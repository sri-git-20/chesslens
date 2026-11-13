import 'package:chesslens/src/board/review_args.dart';
import 'package:chesslens/src/board/review_model.dart';
import 'package:chesslens/src/board/review_screen.dart';
import 'package:chesslens/src/chess/castling.dart';
import 'package:chesslens/src/collections/collection_providers.dart';
import 'package:chesslens/src/collections/memory_collection_repository.dart';
import 'package:chesslens/src/engine/engine_providers.dart';
import 'package:chesslens/src/engine/fake_engine_service.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpReview(WidgetTester tester, ReviewArgs args) async {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        collectionRepositoryProvider.overrideWithValue(MemoryCollectionRepository()),
        engineServiceProvider.overrideWithValue(FakeEngineService()),
      ],
      child: MaterialApp(home: ReviewScreen(args: args)),
    ),
  );
  await tester.pump();
}

ButtonStyleButton button(WidgetTester tester, String label) {
  return tester.widget<ButtonStyleButton>(
    find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()),
  );
}

void main() {
  testWidgets('a position without kings disables Analyze and says why', (tester) async {
    await pumpReview(tester, const ReviewArgs(boardFen: '8/8/8/8/8/8/4P3/8'));

    expect(find.text('White has no king.'), findsOneWidget);
    expect(find.text('Black has no king.'), findsOneWidget);
    expect(find.text('The position is legal.'), findsNothing);
    for (final label in ['Analyze', 'Play', 'Solve', 'Save to collection']) {
      expect(button(tester, label).onPressed, isNull, reason: label);
    }
  });

  testWidgets('a legal position enables Analyze, Play, Solve and Save', (tester) async {
    await pumpReview(tester, const ReviewArgs(boardFen: '4k3/8/8/8/8/8/4P3/4K3'));

    expect(find.text('The position is legal.'), findsOneWidget);
    expect(find.textContaining('has no king'), findsNothing);
    for (final label in ['Analyze', 'Play', 'Solve', 'Save to collection']) {
      expect(button(tester, label).onPressed, isNotNull, reason: label);
    }
  });

  testWidgets('messages follow edits and the side to move', (tester) async {
    // White rook gives check to the black king, with White to move.
    await pumpReview(tester, const ReviewArgs(boardFen: '4k3/8/8/8/8/8/8/K3R3'));
    expect(find.textContaining("Black's king is in check"), findsOneWidget);
    expect(button(tester, 'Analyze').onPressed, isNull);

    await tester.tap(find.text('Black to move'));
    await tester.pump();
    expect(find.textContaining('is in check'), findsNothing);
    expect(button(tester, 'Analyze').onPressed, isNotNull);

    await tester.tap(find.text('Clear board'));
    await tester.pump();
    expect(find.text('White has no king.'), findsOneWidget);

    await tester.tap(find.text('Start position'));
    await tester.pump();
    expect(find.text('The position is legal.'), findsOneWidget);
  });

  testWidgets('an unreadable FEN opens an empty board with a message', (tester) async {
    await pumpReview(tester, const ReviewArgs(boardFen: 'nonsense'));
    await tester.pump();
    expect(find.text('The position could not be read. Set it up on the board.'), findsOneWidget);
    expect(find.text('White has no king.'), findsOneWidget);
  });

  group('ReviewModel', () {
    test('low-confidence squares are flagged until edited', () {
      final confidence = List<double>.filled(64, 1);
      confidence[0] = 0.5; // a8
      confidence[63] = 0.84; // h1
      confidence[10] = 0.85; // exactly the threshold is fine
      final (model, error) = ReviewModel.fromArgs(
        ReviewArgs(boardFen: '8/8/8/8/8/8/8/8', confidence: confidence),
      );
      expect(error, isNull);
      expect(model.flagged, {Square.a8, Square.h1});

      model.putPiece(Square.a8, Piece.blackKing);
      expect(model.flagged, {Square.h1});
    });

    test('castling follows the pieces and can be edited', () {
      final model = ReviewModel(board: Board.parseFen('r3k2r/8/8/8/8/8/8/R3K2R'));
      expect(model.castling, CastlingRights.all);

      model.setCastling(Side.white, CastlingSide.king, false);
      expect(model.castling.fen, 'Qkq');
      expect(model.fullFen, 'r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1');

      // Taking the h8 rook away drops the right; putting it back restores it.
      model.removePiece(Square.h8);
      expect(model.castling.fen, 'Qq');
      model.putPiece(Square.h8, Piece.blackRook);
      expect(model.castling.fen, 'Qkq');

      // A right that the pieces do not allow cannot be switched on.
      model.removePiece(Square.a1);
      model.setCastling(Side.white, CastlingSide.queen, true);
      expect(model.castling.whiteQueenSide, isFalse);
    });

    test('dropping a piece moves it', () {
      final model = ReviewModel(board: Board.parseFen('4k3/8/8/8/8/8/8/4K3'));
      model.dropPiece(Square.e1, Square.d1, Piece.whiteKing);
      expect(model.board.pieceAt(Square.e1), isNull);
      expect(model.board.pieceAt(Square.d1), Piece.whiteKing);
      model.dropPiece(null, Square.a2, Piece.whitePawn);
      expect(model.board.pieceAt(Square.a2), Piece.whitePawn);
    });

    test('flip changes only the view', () {
      final model = ReviewModel(board: Board.standard);
      final fen = model.fullFen;
      model.flip();
      expect(model.orientation, Side.black);
      expect(model.fullFen, fen);
    });
  });
}
