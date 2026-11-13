import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chesslens/src/app_info.dart';
import 'package:chesslens/src/report/app_log.dart';
import 'package:chesslens/src/report/report_builder.dart';
import 'package:chesslens/src/report/report_sender.dart';
import 'package:chesslens/src/report/session_state.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

const environment = ReportEnvironment(
  os: 'Android 14 (API 34)',
  deviceModel: 'Google Pixel 7',
  locale: 'en-US',
  engine: 'Built-in light network; threads 2',
  version: '1.2.3',
  build: '45',
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('chesslens_report_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('report text', () {
    test('subject has version, build and kind', () {
      expect(
        reportSubject(ReportKind.crash, version: '1.2.3', build: '45'),
        '[ChessLens 1.2.3 (45)] Crash report',
      );
      expect(reportSubject(ReportKind.problem, version: '1', build: '2'),
          '[ChessLens 1 (2)] Problem report');
      expect(reportSubject(ReportKind.recognition, version: '1', build: '2'),
          '[ChessLens 1 (2)] Recognition report');
    });

    test('the recipient is the bug report address', () {
      expect(reportRecipient, bugReportEmail);
    });

    test('body lists the environment and the description', () {
      final body = buildReportBody(
        kind: ReportKind.problem,
        description: '  The app froze.  ',
        environment: environment,
      );
      expect(body, contains('The app froze.'));
      expect(body, contains('App: ChessLens 1.2.3 (build 45)'));
      expect(body, contains('System: Android 14 (API 34)'));
      expect(body, contains('Device: Google Pixel 7'));
      expect(body, contains('Locale: en-US'));
      expect(body, contains('Engine: Built-in light network; threads 2'));
      expect(body, isNot(contains('Detected position')));
    });

    test('an empty description says so', () {
      final body = buildReportBody(
        kind: ReportKind.crash,
        description: '   ',
        environment: environment,
      );
      expect(body, contains('(none)'));
    });

    test('recognition body has both positions', () {
      final body = buildReportBody(
        kind: ReportKind.recognition,
        description: '',
        environment: environment,
        recognition: const RecognitionReportData(
          detectedFen: '8/8/8/8/8/8/8/K6k',
          correctedFen: '8/8/8/8/8/8/8/K5k1 w - - 0 1',
        ),
      );
      expect(body, contains('Detected position: 8/8/8/8/8/8/8/K6k'));
      expect(body, contains('Corrected position: 8/8/8/8/8/8/8/K5k1 w - - 0 1'));
    });

    test('describeEngine names the network and the limits', () {
      expect(describeEngine(const AppSettings()), contains('Built-in light network'));
      final full = describeEngine(
        const AppSettings(engineNetworkPath: '/data/x.nnue', depthLimit: 0, engineThreads: 3),
      );
      expect(full, contains('Full network'));
      expect(full, contains('threads 3'));
      expect(full, contains('depth limit none'));
      expect(full, isNot(contains('/data/x.nnue')));
    });
  });

  group('attachments', () {
    final image = Uint8List.fromList([1, 2, 3]);
    final recognition = RecognitionReportData(
      detectedFen: 'a',
      correctedFen: 'b',
      image: image,
    );

    test('a problem report has only the log', () {
      final files = buildAttachments(logText: 'log');
      expect(files.map((f) => f.name), ['chesslens-log.txt']);
    });

    test('a recognition report adds the image and both positions', () {
      final files = buildAttachments(logText: 'log', recognition: recognition);
      expect(
        files.map((f) => f.name),
        ['chesslens-log.txt', 'diagram.png', 'detected-fen.txt', 'corrected-fen.txt'],
      );
      expect(utf8.decode(files[2].bytes), 'a\n');
      expect(utf8.decode(files[3].bytes), 'b\n');
    });

    test('the image can be left out', () {
      final files = buildAttachments(
        logText: 'log',
        recognition: recognition,
        includeImage: false,
      );
      expect(files.map((f) => f.name), isNot(contains('diagram.png')));
      expect(files.length, 3);
    });

    test('the log text has the app log and the engine lines', () {
      final text = buildLogText(appLog: 'line one\n', engineLines: ['engine a', 'engine b']);
      expect(text, contains('line one'));
      expect(text, contains('engine a\nengine b'));
      expect(buildLogText(appLog: '', engineLines: []), contains('(empty)'));
    });

    test('formatFileSize', () {
      expect(formatFileSize(10), '10 B');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(1572864), '1.5 MB');
    });
  });

  group('AppLog', () {
    test('writes timestamped lines and indents extra lines', () {
      final log = AppLog(
        File('${temp.path}/log.txt'),
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      log.info('hello');
      log.error('boom', StateError('bad'), StackTrace.fromString('#0 a\n#1 b'));
      final lines = log.read().trimRight().split('\n');
      expect(lines.first, '2026-01-02T03:04:05.000Z [I] hello');
      expect(lines[1], startsWith('2026-01-02T03:04:05.000Z [E] boom: Bad state: bad'));
      expect(lines[2], '    #0 a');
      expect(lines[3], '    #1 b');
    });

    test('drops the oldest lines when it grows past the limit', () {
      final log = AppLog(File('${temp.path}/log.txt'), maxBytes: 2000);
      for (var i = 0; i < 100; i++) {
        log.info('entry number $i');
      }
      final text = log.read();
      expect(utf8.encode(text).length, lessThanOrEqualTo(2000));
      expect(text, contains('entry number 99'));
      expect(text, isNot(contains('entry number 0\n')));
      // The first kept line is a whole entry.
      expect(text, startsWith(RegExp(r'\d{4}-')));
    });

    test('cuts very long entries', () {
      final log = AppLog(File('${temp.path}/log.txt'));
      log.info('x' * 10000);
      expect(log.read().length, lessThan(AppLog.maxEntryChars + 100));
    });

    test('never throws when the file cannot be written', () {
      final blocked = File('${temp.path}/file.txt')..writeAsStringSync('x');
      final log = AppLog(File('${blocked.path}/inside/log.txt'));
      expect(() => log.info('hello'), returnsNormally);
      expect(log.read(), '');
    });
  });

  group('SessionState', () {
    test('an open marker that is never cleared means a bad exit', () {
      final first = SessionState(temp);
      expect(first.wasOpen, isFalse);
      first.markOpen();
      expect(SessionState(temp).wasOpen, isTrue);
    });

    test('going to the background clears the marker, resume sets it again', () {
      final state = SessionState(temp)..markOpen();
      state.markClosed();
      expect(SessionState(temp).wasOpen, isFalse);
      state.markOpen();
      expect(SessionState(temp).wasOpen, isTrue);
    });

    test('logged errors are remembered until cleared', () {
      final state = SessionState(temp);
      expect(state.hasErrors, isFalse);
      state.markErrors();
      expect(SessionState(temp).hasErrors, isTrue);
      state.clearErrors();
      expect(SessionState(temp).hasErrors, isFalse);
    });
  });

  group('DefaultReportSender', () {
    final message = ReportMessage(
      to: 'dev@example.com',
      subject: 'Subject',
      body: 'Body',
      attachments: [
        ReportAttachment('chesslens-log.txt', Uint8List.fromList(utf8.encode('log'))),
        ReportAttachment('diagram.png', Uint8List.fromList([9, 8, 7])),
      ],
    );

    test('opens the mail app with the files attached', () async {
      Email? sent;
      ShareParams? shared;
      final sender = DefaultReportSender(
        openEmail: (email) async => sent = email,
        openShare: (params) async => shared = params,
        folder: () async => temp,
      );

      expect(await sender.send(message), SendOutcome.mailApp);
      expect(shared, isNull);
      expect(sent!.recipients, ['dev@example.com']);
      expect(sent!.subject, 'Subject');
      expect(sent!.body, 'Body');
      expect(sent!.attachmentPaths!.length, 2);
      expect(File(sent!.attachmentPaths!.first).readAsStringSync(), 'log');
    });

    test('shares the same text and files when there is no mail app', () async {
      ShareParams? shared;
      final sender = DefaultReportSender(
        openEmail: (email) async =>
            throw const FlutterEmailSenderNotAvailableException('no mail app'),
        openShare: (params) async => shared = params,
        folder: () async => temp,
      );

      expect(await sender.send(message), SendOutcome.shareSheet);
      expect(shared!.subject, 'Subject');
      expect(shared!.text, contains('Body'));
      expect(shared!.files!.map((f) => f.name), ['chesslens-log.txt', 'diagram.png']);
    });

    test('other errors are not hidden', () async {
      final sender = DefaultReportSender(
        openEmail: (email) async => throw StateError('broken'),
        openShare: (params) async {},
        folder: () async => temp,
      );
      expect(() => sender.send(message), throwsStateError);
    });
  });
}
