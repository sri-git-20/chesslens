import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_info.dart';
import 'report_builder.dart';

/// What the report screen hands over.
@immutable
class ReportMessage {
  const ReportMessage({
    required this.to,
    required this.subject,
    required this.body,
    required this.attachments,
  });

  final String to;
  final String subject;
  final String body;
  final List<ReportAttachment> attachments;
}

enum SendOutcome { mailApp, shareSheet }

abstract interface class ReportSender {
  /// Opens the mail app (or the share sheet when there is none). Nothing is
  /// sent until the user taps Send there. Throws when both fail.
  Future<SendOutcome> send(ReportMessage message);
}

typedef EmailOpener = Future<void> Function(Email email);
typedef ShareOpener = Future<void> Function(ShareParams params);
typedef FolderProvider = Future<Directory> Function();

/// Opens the mail app with the files attached; if no mail app is available,
/// shares the same text and files with the share sheet.
class DefaultReportSender implements ReportSender {
  DefaultReportSender({
    EmailOpener? openEmail,
    ShareOpener? openShare,
    FolderProvider? folder,
  })  : _openEmail = openEmail ?? _defaultEmail,
        _openShare = openShare ?? _defaultShare,
        _folder = folder ?? getTemporaryDirectory;

  final EmailOpener _openEmail;
  final ShareOpener _openShare;
  final FolderProvider _folder;

  static Future<void> _defaultEmail(Email email) => FlutterEmailSender.send(email);

  static Future<void> _defaultShare(ShareParams params) async {
    await SharePlus.instance.share(params);
  }

  @override
  Future<SendOutcome> send(ReportMessage message) async {
    final paths = await _writeFiles(message.attachments);
    try {
      await _openEmail(
        Email(
          recipients: [message.to],
          subject: message.subject,
          body: message.body,
          attachmentPaths: paths,
        ),
      );
      return SendOutcome.mailApp;
    } on FlutterEmailSenderException {
      // No mail app: fall through to the share sheet.
    }
    await _openShare(
      ShareParams(
        subject: message.subject,
        text: '${message.to}\n\n${message.body}',
        files: [for (final path in paths) XFile(path)],
      ),
    );
    return SendOutcome.shareSheet;
  }

  Future<List<String>> _writeFiles(List<ReportAttachment> attachments) async {
    final root = await _folder();
    final folder = Directory(p.join(root.path, 'report'));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    await folder.create(recursive: true);
    final paths = <String>[];
    for (final attachment in attachments) {
      final file = File(p.join(folder.path, attachment.name));
      await file.writeAsBytes(attachment.bytes, flush: true);
      paths.add(file.path);
    }
    return paths;
  }
}

final reportSenderProvider = Provider<ReportSender>((ref) => DefaultReportSender());

/// The address reports go to.
const String reportRecipient = bugReportEmail;
