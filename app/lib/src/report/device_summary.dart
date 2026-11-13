import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Operating system and device model, as plain text.
@immutable
class DeviceSummary {
  const DeviceSummary({required this.os, required this.model});

  static const unknown = DeviceSummary(os: 'unknown', model: 'unknown');

  final String os;
  final String model;
}

Future<DeviceSummary> readDeviceSummary() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return DeviceSummary(
        os: 'Android ${info.version.release} (API ${info.version.sdkInt})',
        model: '${info.manufacturer} ${info.model}',
      );
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return DeviceSummary(
        os: 'iOS ${info.systemVersion}',
        model: info.utsname.machine,
      );
    }
  } catch (_) {
    // Fall through: a report without device details is still useful.
  }
  return DeviceSummary(os: Platform.operatingSystem, model: 'unknown');
}

/// Tests override this.
final deviceSummaryProvider = FutureProvider<DeviceSummary>((ref) => readDeviceSummary());
