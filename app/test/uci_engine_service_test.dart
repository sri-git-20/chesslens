import 'dart:async';

import 'package:chesslens/src/engine/engine_service.dart';
import 'package:chesslens/src/engine/uci_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

const String startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// A scripted engine: records what it is sent and answers like Stockfish.
class FakeProcess implements UciProcess {
  FakeProcess({this.answerStop = true, this.finishOnGo = false});

  final bool answerStop;
  final bool finishOnGo;
  final StreamController<String> _out = StreamController<String>.broadcast();
  final List<String> sent = [];
  bool searching = false;
  bool disposed = false;
  bool ended = false;

  @override
  Stream<String> get output => _out.stream;

  void emit(String line) {
    if (!_out.isClosed) _out.add(line);
  }

  /// The engine dies without being asked to.
  void crash() {
    ended = true;
    _out.close();
  }

  @override
  void send(String command) {
    if (ended) throw StateError('ended');
    sent.add(command);
    Future<void>.microtask(() {
      if (ended) return;
      if (command == 'uci') {
        emit('id name Stockfish test');
        emit('option name Threads type spin default 1 min 1 max 1024');
        emit('option name Hash type spin default 16 min 1 max 33554432');
        emit('option name UCI_Elo type spin default 1320 min 1320 max 3190');
        emit('uciok');
      } else if (command == 'isready') {
        emit('readyok');
      } else if (command.startsWith('go')) {
        searching = true;
        emit('info depth 1 seldepth 1 multipv 1 score cp 20 nodes 20 nps 1000 time 1 pv e2e4 e7e5');
        emit('info depth 2 seldepth 2 multipv 1 score cp 25 lowerbound nodes 40 pv e2e4');
        emit('info depth 2 seldepth 2 multipv 1 score cp 30 nodes 50 pv e2e4 e7e5');
        if (finishOnGo || command.contains('depth 2') || command.contains('movetime')) {
          finishSearch();
        }
      } else if (command == 'stop' && searching && answerStop) {
        finishSearch();
      }
    });
  }

  void finishSearch() {
    searching = false;
    emit('bestmove e2e4 ponder e7e5');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    ended = true;
    if (!_out.isClosed) await _out.close();
  }
}

void main() {
  late List<FakeProcess> processes;
  late List<String> log;
  late List<EngineSpec> specs;
  late UciEngineService service;

  setUp(() {
    processes = [];
    log = [];
    specs = [];
    service = UciEngineService(
      processFactory: (spec) async {
        specs.add(spec);
        final process = FakeProcess();
        processes.add(process);
        return process;
      },
      settings: const EngineSettings(threads: 3, hashMb: 128),
      stopTimeout: const Duration(milliseconds: 300),
      readyTimeout: const Duration(seconds: 2),
      log: log.add,
    );
  });

  tearDown(() => service.dispose());

  test('starts the engine on first use and reads the Elo range', () async {
    expect(processes, isEmpty);
    final range = await service.eloRange();
    expect(range.min, 1320);
    expect(range.max, 3190);
    expect(processes, hasLength(1));
    expect(service.status.value, EngineStatus.ready);
    expect(processes.single.sent, ['uci', 'isready']);
  });

  test('sends stop-free, ordered commands for a limited search', () async {
    final updates = await service
        .analyze(const AnalysisRequest(
          fen: startFen,
          limit: SearchLimit(depth: 2, movetimeMs: 500),
          multiPv: 2,
        ))
        .toList();

    final sent = processes.single.sent;
    expect(sent.sublist(0, 2), ['uci', 'isready']);
    // Options, then isready, then position, then go.
    final optionsEnd = sent.lastIndexWhere((c) => c.startsWith('setoption'));
    expect(sent[optionsEnd + 1], 'isready');
    expect(sent[optionsEnd + 2], 'position fen $startFen');
    expect(sent[optionsEnd + 3], 'go depth 2 movetime 500');
    expect(sent, contains('setoption name Threads value 3'));
    expect(sent, contains('setoption name Hash value 128'));
    expect(sent, contains('setoption name MultiPV value 2'));
    expect(sent, contains('setoption name UCI_LimitStrength value false'));

    expect(updates.last.isFinal, isTrue);
    expect(updates.last.bestMove, 'e2e4');
    // The lowerbound line is not shown, the exact lines are.
    final scores = updates.where((u) => !u.isFinal).map((u) => u.best!.score.cp).toList();
    expect(scores, [20, 30]);
    expect(updates.last.best!.pv, ['e2e4', 'e7e5']);
  });

  test('a new search stops the old one first and waits for its bestmove', () async {
    final first = service.analyze(const AnalysisRequest(fen: startFen));
    final firstUpdates = <AnalysisUpdate>[];
    var firstDone = false;
    first.listen(firstUpdates.add, onDone: () => firstDone = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(processes.single.searching, isTrue);

    final second = service.analyze(
      const AnalysisRequest(fen: startFen, limit: SearchLimit(depth: 2)),
    );
    final secondUpdates = await second.toList();
    expect(secondUpdates.last.isFinal, isTrue);

    final sent = processes.single.sent;
    final goIndexes = [
      for (var i = 0; i < sent.length; i++)
        if (sent[i].startsWith('go')) i,
    ];
    expect(goIndexes, hasLength(2));
    final stopIndex = sent.indexOf('stop');
    expect(stopIndex, greaterThan(goIndexes[0]));
    expect(stopIndex, lessThan(goIndexes[1]));
    // After stop, isready comes before the next position command.
    final afterStop = sent.sublist(stopIndex);
    expect(afterStop.indexOf('isready'), greaterThan(0));
    expect(afterStop.indexOf('isready'),
        lessThan(afterStop.indexOf('position fen $startFen')));

    expect(firstDone, isTrue);
    expect(firstUpdates.any((u) => u.isFinal), isFalse);
  });

  test('cancelling the subscription stops the search', () async {
    final subscription = service
        .analyze(const AnalysisRequest(fen: startFen))
        .listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(processes.single.sent, contains('stop'));
    expect(processes.single.searching, isFalse);
  });

  test('strength options are sent for Elo and Skill Level', () async {
    await service
        .analyze(const AnalysisRequest(
          fen: startFen,
          limit: SearchLimit(depth: 2),
          strength: EngineStrength.elo(1800),
        ))
        .toList();
    var sent = processes.single.sent;
    expect(sent, contains('setoption name UCI_LimitStrength value true'));
    expect(sent, contains('setoption name UCI_Elo value 1800'));

    processes.single.sent.clear();
    await service
        .analyze(const AnalysisRequest(
          fen: startFen,
          limit: SearchLimit(depth: 2),
          strength: EngineStrength.skill(5),
        ))
        .toList();
    sent = processes.single.sent;
    expect(sent, contains('setoption name UCI_LimitStrength value false'));
    expect(sent, contains('setoption name Skill Level value 5'));
    // Unchanged options are not sent again.
    expect(sent.where((c) => c.contains('Threads')), isEmpty);
  });

  test('searchmoves is the last part of go', () async {
    await service
        .analyze(const AnalysisRequest(
          fen: startFen,
          limit: SearchLimit(depth: 2),
          searchMoves: ['e2e4', 'd2d4'],
        ))
        .toList();
    expect(processes.single.sent.last, 'go depth 2 searchmoves e2e4 d2d4');
  });

  test('illegal positions never reach the engine', () {
    expect(
      () => service.analyze(const AnalysisRequest(fen: '8/8/8/8/8/8/8/8 w - - 0 1')),
      throwsA(isA<IllegalPositionException>()),
    );
    expect(
      () => service.analyze(const AnalysisRequest(fen: '4k3/8/8/8/8/8/8/K3R3 w - - 0 1')),
      throwsA(isA<IllegalPositionException>()),
    );
    expect(processes, isEmpty);
  });

  test('a crash during a search recreates the engine and runs the search again', () async {
    final created = <FakeProcess>[];
    final crashing = UciEngineService(
      // The first engine searches forever (and is killed), the second answers.
      processFactory: (spec) async {
        final process = FakeProcess(finishOnGo: created.isNotEmpty);
        created.add(process);
        return process;
      },
      log: log.add,
    );
    addTearDown(crashing.dispose);

    final updates = <AnalysisUpdate>[];
    final done = Completer<void>();
    crashing
        .analyze(const AnalysisRequest(fen: startFen))
        .listen(updates.add, onDone: done.complete);
    // Kill the first engine as soon as it has started searching.
    while (created.isEmpty || !created.first.sent.any((c) => c.startsWith('go'))) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    created.first.crash();
    await done.future.timeout(const Duration(seconds: 5));

    expect(created, hasLength(2));
    expect(updates.last.isFinal, isTrue);
    expect(log.any((m) => m.contains('ended unexpectedly')), isTrue);
  });

  test('a crash while idle is repaired on the next search', () async {
    await service.ensureStarted();
    processes.single.crash();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.status.value, EngineStatus.failed);

    final updates = await service
        .analyze(const AnalysisRequest(fen: startFen, limit: SearchLimit(depth: 2)))
        .toList();
    expect(processes, hasLength(2));
    expect(updates.last.isFinal, isTrue);
    expect(service.status.value, EngineStatus.ready);
  });

  test('a start failure is reported as a stream error', () async {
    final failing = UciEngineService(
      processFactory: (spec) async => throw StateError('no native library'),
      log: log.add,
    );
    addTearDown(failing.dispose);
    await expectLater(
      failing.analyze(const AnalysisRequest(fen: startFen)),
      emitsError(isA<EngineFailure>()),
    );
    expect(failing.status.value, EngineStatus.failed);
  });

  test('restart switches to the given build', () async {
    await service.ensureStarted();
    await service.restart(EngineSpec.light);
    expect(processes.first.disposed, isTrue);
    expect(service.spec, EngineSpec.light);
    await service.ensureStarted();
    expect(processes, hasLength(2));

    final full = EngineSpec.forNetworkPath('/data/nn-1a298aa575a0.nnue');
    expect(full.nnuePath, '/data/nn-1a298aa575a0.nnue');
    await service.restart(full);
    expect(service.spec, full);
    await service.ensureStarted();
    expect(specs.last, full);
    expect(EngineSpec.forNetworkPath(null), EngineSpec.light);
  });
}
