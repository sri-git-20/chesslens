import 'dart:io';
import 'dart:typed_data';

import 'package:chesslens/src/report/app_log.dart';
import 'package:chesslens/src/report/crash_prompt.dart';
import 'package:chesslens/src/report/device_summary.dart';
import 'package:chesslens/src/report/report_builder.dart';
import 'package:chesslens/src/report/report_screen.dart';
import 'package:chesslens/src/report/report_sender.dart';
import 'package:chesslens/src/report/reporting.dart';
import 'package:chesslens/src/report/session_state.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSender implements ReportSender {
  ReportMessage? sent;

  @override
  Future<SendOutcome> send(ReportMessage message) async {
    sent = message;
    return SendOutcome.mailApp;
  }
}

void main() {
  late Directory temp;
  late Reporting reporting;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('chesslens_screen_');
    reporting = Reporting(
      log: AppLog(File('${temp.path}/log.txt'))..info('hello from the log'),
      session: SessionState(temp),
      previousSessionProblem: true,
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<Widget> app(Widget home, FakeSender sender) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        reportingProvider.overrideWithValue(reporting),
        reportSenderProvider.overrideWithValue(sender),
        deviceSummaryProvider.overrideWith(
          (ref) async => const DeviceSummary(os: 'Android 14 (API 34)', model: 'Test Phone'),
        ),
      ],
      child: MaterialApp(home: home),
    );
  }

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the crash prompt asks once and Not now dismisses it', (tester) async {
    final sender = FakeSender();
    await tester.pumpWidget(
      await app(const CrashReportPrompt(child: Scaffold(body: Text('Home'))), sender),
    );
    await tester.pumpAndSettle();

    expect(find.text('ChessLens closed unexpectedly last time. Send a report?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('closed unexpectedly'), findsNothing);
    expect(reporting.previousSessionProblem, isFalse);
    expect(sender.sent, isNull);
  });

  testWidgets('no prompt when the last session was fine', (tester) async {
    reporting.previousSessionProblem = false;
    await tester.pumpWidget(
      await app(const CrashReportPrompt(child: Scaffold(body: Text('Home'))), FakeSender()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('closed unexpectedly'), findsNothing);
  });

  testWidgets('Send report opens the preview', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(
      await app(const CrashReportPrompt(child: Scaffold(body: Text('Home'))), FakeSender()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(find.text('Crash report'), findsOneWidget);
    expect(find.textContaining('exactly what will be sent'), findsOneWidget);
  });

  testWidgets('the preview shows what is sent and Send hands it over', (tester) async {
    tallScreen(tester);
    final sender = FakeSender();
    await tester.pumpWidget(
      await app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openReportScreen(context, kind: ReportKind.problem),
              child: const Text('Open'),
            ),
          ),
        ),
        sender,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Problem report'), findsOneWidget);
    expect(find.text('proxify1@gmail.com'), findsOneWidget);
    expect(find.textContaining('Device: Test Phone'), findsOneWidget);
    expect(find.text('chesslens-log.txt'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'The board is upside down');
    await tester.pump();
    expect(find.textContaining('The board is upside down'), findsWidgets);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    final message = sender.sent!;
    expect(message.to, 'proxify1@gmail.com');
    expect(message.subject, endsWith('Problem report'));
    expect(message.body, contains('The board is upside down'));
    expect(message.body, contains('Device: Test Phone'));
    expect(message.attachments.map((a) => a.name), ['chesslens-log.txt']);
    expect(String.fromCharCodes(message.attachments.single.bytes), contains('hello from the log'));
    // Back on the first screen, with a note about the mail app.
    expect(find.text('Open'), findsOneWidget);
    expect(find.textContaining('mail app is open'), findsOneWidget);
  });

  testWidgets('a recognition report can leave out the image', (tester) async {
    tallScreen(tester);
    final sender = FakeSender();
    // A 1x1 transparent PNG.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
      0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
      0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8,
      0xFF, 0xFF, 0x3F, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
      0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    await tester.pumpWidget(
      await app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openReportScreen(
                context,
                kind: ReportKind.recognition,
                recognition: RecognitionReportData(
                  detectedFen: '8/8/8/8/8/8/8/K6k',
                  correctedFen: '8/8/8/8/8/8/8/K5k1 w - - 0 1',
                  image: png,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        sender,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('diagram.png'), findsOneWidget);
    expect(find.text('detected-fen.txt'), findsOneWidget);
    await tester.tap(find.text('Include the image'));
    await tester.pumpAndSettle();
    expect(find.text('diagram.png'), findsNothing);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(
      sender.sent!.attachments.map((a) => a.name),
      ['chesslens-log.txt', 'detected-fen.txt', 'corrected-fen.txt'],
    );
    expect(sender.sent!.body, contains('Detected position: 8/8/8/8/8/8/8/K6k'));
  });
}
