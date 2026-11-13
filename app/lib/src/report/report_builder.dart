import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../settings/settings_controller.dart';

enum ReportKind {
  crash('Crash'),
  problem('Problem'),
  recognition('Recognition');

  const ReportKind(this.label);

  final String label;
}

/// Facts about the phone and the app that go into a report.
@immutable
class ReportEnvironment {
  const ReportEnvironment({
    required this.os,
    required this.deviceModel,
    required this.locale,
    required this.engine,
    this.version = appVersion,
    this.build = buildNumber,
  });

  final String version;
  final String build;
  final String os;
  final String deviceModel;
  final String locale;

  /// See [describeEngine].
  final String engine;
}

/// The two positions of a recognition report.
@immutable
class RecognitionReportData {
  const RecognitionReportData({
    required this.detectedFen,
    required this.correctedFen,
    this.image,
  });

  /// What the recognizer found (as passed to Review).
  final String detectedFen;

  /// What the user ended up with.
  final String correctedFen;

  /// PNG of the diagram, or `null`.
  final Uint8List? image;
}

/// A file that goes with a report.
@immutable
class ReportAttachment {
  const ReportAttachment(this.name, this.bytes, {this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;

  int get size => bytes.length;
}

String reportSubject(
  ReportKind kind, {
  String version = appVersion,
  String build = buildNumber,
}) =>
    '[$appName $version ($build)] ${kind.label} report';

/// A short text about the engine for reports: which network, and the
/// settings that matter.
String describeEngine(AppSettings settings) {
  final network = settings.engineNetworkPath == null
      ? 'Built-in light network'
      : 'Full network (downloaded)';
  final depth = settings.depthLimit == 0 ? 'none' : '${settings.depthLimit}';
  final time = settings.timeLimitSeconds == 0 ? 'none' : '${settings.timeLimitSeconds} s';
  return '$network; threads ${settings.engineThreads}, hash ${settings.engineHashMb} MB, '
      'lines ${settings.multiPv}, depth limit $depth, time limit $time';
}

/// The text of the e-mail. [description] is what the user typed.
String buildReportBody({
  required ReportKind kind,
  required String description,
  required ReportEnvironment environment,
  RecognitionReportData? recognition,
}) {
  final text = description.trim();
  final buffer = StringBuffer()
    ..writeln('Description:')
    ..writeln(text.isEmpty ? '(none)' : text)
    ..writeln()
    ..writeln('Report type: ${kind.label}')
    ..writeln('App: $appName ${environment.version} (build ${environment.build})')
    ..writeln('System: ${environment.os}')
    ..writeln('Device: ${environment.deviceModel}')
    ..writeln('Locale: ${environment.locale}')
    ..writeln('Engine: ${environment.engine}');
  if (recognition != null) {
    buffer
      ..writeln()
      ..writeln('Detected position: ${recognition.detectedFen}')
      ..writeln('Corrected position: ${recognition.correctedFen}');
  }
  return buffer.toString().trimRight();
}

/// The log file text for a report: the app log, then the last engine lines.
String buildLogText({required String appLog, required List<String> engineLines}) {
  final buffer = StringBuffer()
    ..writeln('=== ChessLens log ===')
    ..writeln(appLog.trim().isEmpty ? '(empty)' : appLog.trimRight())
    ..writeln()
    ..writeln('=== Engine log (last ${engineLines.length} lines) ===');
  if (engineLines.isEmpty) {
    buffer.writeln('(empty)');
  } else {
    engineLines.forEach(buffer.writeln);
  }
  return buffer.toString();
}

/// The files to attach. The image is left out when [includeImage] is false.
List<ReportAttachment> buildAttachments({
  required String logText,
  RecognitionReportData? recognition,
  bool includeImage = true,
}) {
  Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));
  return [
    ReportAttachment('chesslens-log.txt', text(logText), mimeType: 'text/plain'),
    if (recognition != null) ...[
      if (includeImage && recognition.image != null)
        ReportAttachment('diagram.png', recognition.image!, mimeType: 'image/png'),
      ReportAttachment(
        'detected-fen.txt',
        text('${recognition.detectedFen}\n'),
        mimeType: 'text/plain',
      ),
      ReportAttachment(
        'corrected-fen.txt',
        text('${recognition.correctedFen}\n'),
        mimeType: 'text/plain',
      ),
    ],
  ];
}

/// "12 KB" or "1.2 MB" for the attachment list.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
