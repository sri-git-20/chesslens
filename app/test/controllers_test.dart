import 'dart:async';

import 'package:chesslens/src/analysis/analysis_controller.dart';
import 'package:chesslens/src/collections/memory_collection_repository.dart';
import 'package:chesslens/src/collections/models.dart';
import 'package:chesslens/src/engine/engine_service.dart';
import 'package:chesslens/src/engine/fake_engine_service.dart';
import 'package:chesslens/src/engine/play_levels.dart';
import 'package:chesslens/src/engine/uci.dart';
import 'package:chesslens/src/play/play_controller.dart';
import 'package:chesslens/src/solve/solve_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

EngineLine line(String move, UciScore score, {int depth = 12, int multiPv = 1}) => EngineLine(
      multiPv: multiPv,
      depth: depth,
      score: score,
      pv: [move],
    );

void main() {
  group('AnalysisController', () {
    late FakeEngineService engine;

    setUp(() => engine = FakeEngineService());

    test('searches the start position and every position after a move', () async {
      final controller = AnalysisController(start: Chess.initial, engine: engine)..start();
      addTearDown(controller.dispose);
      await until(() => controller.lines.isNotEmpty, reason: 'first lines');
      expect(engine.requests.single.fen, Chess.initial.fen);
      expect(engine.requests.single.multiPv, 2);
      expect(engine.requests.single.limit.depth, 30);
      expect(engine.requests.single.limit.movetimeMs, 60000);

      controller.makeMove(NormalMove.fromUci('e2e4'));
      expect(controller.tree.current.san, 'e4');
      await until(() => engine.requests.length == 2, reason: 'second search');
      expect(engine.requests.last.fen, contains('4P3'));

      controller.back();
      expect(controller.position.fen, Chess.initial.fen);
      controller.forward();
      expect(controller.lastMove, NormalMove.fromUci('e2e4'));
    });

    test('depth and time limits of 0 mean no limit', () async {
      final controller = AnalysisController(
        start: Chess.initial,
        engine: engine,
        config: const AnalysisConfig(multiPv: 3, depthLimit: 0, timeLimitSeconds: 0),
      )..start();
      addTearDown(controller.dispose);
      expect(engine.requests.single.limit.isInfinite, isTrue);
      expect(engine.requests.single.multiPv, 3);
    });

    test('engine off, hidden and game over do not search', () async {
      final controller = AnalysisController(start: Chess.initial, engine: engine)..start();
      addTearDown(controller.dispose);
      await until(() => controller.lines.isNotEmpty);

      controller.setEngineOn(false);
      expect(controller.idle, AnalysisIdle.off);
      expect(controller.lines, isEmpty);
      controller.setEngineOn(true);
      expect(engine.requests, hasLength(2));

      controller.setVisible(false);
      expect(controller.idle, AnalysisIdle.hidden);
      expect(engine.requests, hasLength(2));
      controller.setVisible(true);
      expect(engine.requests, hasLength(3));

      final mated = Chess.fromSetup(Setup.parseFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'));
      final over = AnalysisController(start: mated, engine: engine)..start();
      addTearDown(over.dispose);
      expect(over.idle, AnalysisIdle.gameOver);
      expect(engine.requests, hasLength(3));
    });

    test('changing the config starts a new search; disposing stops the engine', () async {
      final controller = AnalysisController(start: Chess.initial, engine: engine)..start();
      controller.updateConfig(const AnalysisConfig(multiPv: 1, depthLimit: 20, timeLimitSeconds: 10));
      expect(engine.requests.last.multiPv, 1);
      expect(engine.requests.last.limit.depth, 20);
      final stops = engine.stops;
      controller.dispose();
      expect(engine.stops, stops + 1);
    });

    test('engine failures are shown, not thrown', () async {
      final failing = _FailingEngine();
      final controller = AnalysisController(start: Chess.initial, engine: failing)..start();
      addTearDown(controller.dispose);
      await until(() => controller.idle == AnalysisIdle.failed);
      expect(controller.error, 'No engine here.');
    });
  });

  group('PlayController', () {
    test('plays a move, the engine answers, takeback undoes both', () async {
      final engine = FakeEngineService();
      final controller = PlayController(start: Chess.initial, engine: engine);
      addTearDown(controller.dispose);

      await controller.startGame(userSide: Side.white, level: PlayLevel.levels[0]);
      expect(controller.isUserTurn, isTrue);
      expect(controller.canTakeback, isFalse);

      controller.userMove(NormalMove.fromUci('e2e4'));
      expect(controller.isThinking, isTrue);
      await until(() => controller.isUserTurn, reason: 'engine reply');
      expect(controller.moves, hasLength(2));
      expect(engine.requests.single.limit.movetimeMs, 150);
      expect(engine.requests.single.strength, const EngineStrength.skill(0));
      expect(engine.requests.single.newGame, isTrue);
      expect(controller.canTakeback, isTrue);

      controller.takeback();
      expect(controller.moves, isEmpty);
      expect(controller.position.fen, Chess.initial.fen);
      expect(controller.isUserTurn, isTrue);
    });

    test('the engine moves first when the user plays Black', () async {
      final engine = FakeEngineService();
      final controller = PlayController(start: Chess.initial, engine: engine);
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.black, level: PlayLevel.fullStrength);
      await until(() => controller.isUserTurn, reason: 'engine opening move');
      expect(controller.moves, hasLength(1));
      expect(engine.requests.single.strength.isFull, isTrue);
    });

    test('moves are ignored when it is not the user\'s turn', () async {
      final controller = PlayController(start: Chess.initial, engine: FakeEngineService());
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.black, level: PlayLevel.fullStrength);
      controller.userMove(NormalMove.fromUci('e2e4'));
      await until(() => controller.isUserTurn);
      expect(controller.moves, hasLength(1));
    });

    test('hint suggests the engine move', () async {
      final engine = FakeEngineService(
        evaluator: (request) => FakeResult(
          lines: [line('d2d4', const UciScore.cp(30))],
          bestMove: 'd2d4',
        ),
      );
      final controller = PlayController(start: Chess.initial, engine: engine);
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.white, level: PlayLevel.levels[3]);
      controller.showHint();
      expect(controller.isHintLoading, isTrue);
      await until(() => controller.hint != null, reason: 'hint');
      expect(controller.hint, NormalMove.fromUci('d2d4'));
      expect(engine.requests.last.strength.isFull, isTrue);
    });

    test('resigning ends the game', () async {
      final controller = PlayController(start: Chess.initial, engine: FakeEngineService());
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.white, level: PlayLevel.levels[3]);
      controller.resign();
      expect(controller.end!.reason.name, 'resignation');
      expect(controller.resultText, 'You resigned. The engine wins.');
      expect(controller.isUserTurn, isFalse);
    });

    test('checkmate ends the game with a result', () async {
      final start = Chess.fromSetup(Setup.parseFen('6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1'));
      final controller = PlayController(start: start, engine: FakeEngineService());
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.white, level: PlayLevel.levels[3]);
      controller.userMove(NormalMove.fromUci('a1a8'));
      expect(controller.resultText, 'Checkmate. You win!');
      expect(controller.isThinking, isFalse);
    });
  });

  group('PlayController on finished positions', () {
    test('a position that is already mate ends the game without asking the engine', () async {
      final start = Chess.fromSetup(Setup.parseFen('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1'));
      final engine = FakeEngineService();
      final controller = PlayController(start: start, engine: engine);
      addTearDown(controller.dispose);
      await controller.startGame(userSide: Side.black, level: PlayLevel.levels[3]);
      expect(controller.end?.reason.name, 'checkmate');
      expect(controller.resultText, 'Checkmate. The engine wins.');
      expect(controller.isThinking, isFalse);
      expect(controller.isUserTurn, isFalse);
      expect(engine.requests, isEmpty);
    });

    test('starting another game while the first is still loading does not start the old one', () async {
      final engine = FakeEngineService();
      final controller = PlayController(start: Chess.initial, engine: engine);
      addTearDown(controller.dispose);
      final first = controller.startGame(userSide: Side.black, level: PlayLevel.levels[3]);
      controller.newGame();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.started, isFalse);
      expect(engine.requests, isEmpty);
    });
  });

  group('SolveController', () {
    const mateInOne = '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1';

    // Ra8# is the only winning move; everything else evaluates to 0.00.
    FakeResult evaluator(AnalysisRequest request) {
      final searched = request.searchMoves;
      final move = searched.isEmpty ? 'a1a8' : searched.first;
      final mates = move == 'a1a8';
      return FakeResult(
        lines: [line(move, mates ? const UciScore.mate(1) : const UciScore.cp(0), depth: 20)],
        bestMove: move,
      );
    }

    const instant = SolveSearch(solutionDelay: Duration.zero);

    test('the best move solves the puzzle and is recorded', () async {
      final repository = MemoryCollectionRepository();
      final collection = await repository.createCollection('Mates');
      final puzzle = await repository.addPuzzle(Puzzle(
        id: 0,
        collectionId: collection.id,
        fen: mateInOne,
        orientation: Side.white,
        createdAt: DateTime(2026),
      ));
      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(mateInOne)),
        engine: FakeEngineService(evaluator: evaluator),
        puzzleId: puzzle.id,
        repository: repository,
        search: instant,
      );
      addTearDown(controller.dispose);

      expect(controller.canMove, isTrue);
      controller.userMove(NormalMove.fromUci('a1a8'));
      expect(controller.phase, SolvePhase.judging);
      await until(() => controller.phase == SolvePhase.finished, reason: 'finish');
      expect(controller.resultText, 'Checkmate. Puzzle solved!');
      expect(controller.usedSolution, isFalse);

      await controller.recordSession();
      await controller.recordSession(); // counted once
      final saved = (await repository.getPuzzle(puzzle.id))!;
      expect(saved.status, PuzzleStatus.solved);
      expect(saved.attempts, 1);
    });

    test('a wrong move can be taken back, then solved', () async {
      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(mateInOne)),
        engine: FakeEngineService(evaluator: evaluator),
        search: instant,
      );
      addTearDown(controller.dispose);

      controller.userMove(NormalMove.fromUci('a1a7'));
      await until(() => controller.phase == SolvePhase.wrong, reason: 'wrong verdict');
      expect(controller.position.fen, isNot(startsWith('6k1/5ppp/8/8/8/8/8/R3K3')));

      controller.tryAgain();
      expect(controller.phase, SolvePhase.yourMove);
      expect(controller.position.fen, startsWith('6k1/5ppp/8/8/8/8/8/R3K3 w'));

      controller.userMove(NormalMove.fromUci('a1a8'));
      await until(() => controller.phase == SolvePhase.finished);
      expect(controller.usedSolution, isFalse);
    });

    test('Show solution plays the engine line and counts as failed', () async {
      final repository = MemoryCollectionRepository();
      final collection = await repository.createCollection('Mates');
      final puzzle = await repository.addPuzzle(Puzzle(
        id: 0,
        collectionId: collection.id,
        fen: mateInOne,
        orientation: Side.white,
        createdAt: DateTime(2026),
      ));
      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(mateInOne)),
        engine: FakeEngineService(evaluator: evaluator),
        puzzleId: puzzle.id,
        repository: repository,
        search: instant,
      );
      addTearDown(controller.dispose);

      controller.userMove(NormalMove.fromUci('a1a7'));
      await until(() => controller.phase == SolvePhase.wrong);
      unawaited(controller.showSolution());
      await until(() => controller.phase == SolvePhase.finished, reason: 'solution');
      expect(controller.usedSolution, isTrue);
      expect(controller.resultText, 'Solution shown.');
      expect(controller.position.isCheckmate, isTrue);

      await controller.recordSession();
      final saved = (await repository.getPuzzle(puzzle.id))!;
      expect(saved.status, PuzzleStatus.failed);
      expect(saved.attempts, 1);
    });

    test('the opponent answers with the engine move and the puzzle goes on', () async {
      // Winning a queen: after the correct move Black replies and it is the
      // user's turn again.
      const fen = '4k3/8/8/8/8/8/4q3/R3K3 w - - 0 1';
      FakeResult scripted(AnalysisRequest request) {
        final position = Chess.fromSetup(Setup.parseFen(request.fen));
        if (position.turn == Side.white) {
          final move = request.searchMoves.isEmpty ? 'e1e2' : request.searchMoves.first;
          return FakeResult(
            lines: [line(move, UciScore.cp(move == 'e1e2' ? 900 : 0), depth: 20)],
            bestMove: move,
          );
        }
        return FakeResult(lines: [line('e8d8', const UciScore.cp(-900))], bestMove: 'e8d8');
      }

      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(fen)),
        engine: FakeEngineService(evaluator: scripted),
        search: instant,
      );
      addTearDown(controller.dispose);
      controller.userMove(NormalMove.fromUci('e1e2'));
      await until(() => controller.phase == SolvePhase.yourMove && controller.movesPlayed == 1,
          reason: 'opponent reply');
      expect(controller.position.turn, Side.white);
      expect(controller.lastMove, NormalMove.fromUci('e8d8'));
    });

    test('a hint highlights the piece to move', () async {
      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(mateInOne)),
        engine: FakeEngineService(evaluator: evaluator),
        search: instant,
      );
      addTearDown(controller.dispose);
      await controller.showHint();
      expect(controller.hintSquare, Square.a1);
    });

    test('nothing is recorded when no move was tried', () async {
      final repository = MemoryCollectionRepository();
      final collection = await repository.createCollection('Mates');
      final puzzle = await repository.addPuzzle(Puzzle(
        id: 0,
        collectionId: collection.id,
        fen: mateInOne,
        orientation: Side.white,
        createdAt: DateTime(2026),
      ));
      final controller = SolveController(
        start: Chess.fromSetup(Setup.parseFen(mateInOne)),
        engine: FakeEngineService(evaluator: evaluator),
        puzzleId: puzzle.id,
        repository: repository,
        search: instant,
      );
      addTearDown(controller.dispose);
      await controller.recordSession();
      expect((await repository.getPuzzle(puzzle.id))!.attempts, 0);
    });
  });
}

class _FailingEngine extends FakeEngineService {
  @override
  Stream<AnalysisUpdate> analyze(AnalysisRequest request) =>
      Stream<AnalysisUpdate>.error(const EngineFailure('No engine here.'));
}
