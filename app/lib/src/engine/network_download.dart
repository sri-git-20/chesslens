import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../report/reporting.dart';
import '../settings/settings_controller.dart';

/// The full-strength network, `Stockfish.latestNNUE` in multistockfish.
const String networkFileName = 'nn-1a298aa575a0.nnue';

/// The first 12 hex characters of the file's SHA-256 are the id in its name.
const String networkHashPrefix = '1a298aa575a0';

/// Tried in this order.
const List<String> networkUrls = [
  'https://tests.stockfishchess.org/api/nn/$networkFileName',
  'https://github.com/official-stockfish/networks/raw/master/$networkFileName',
];

/// "42 MB", rounded, never less than 1 MB.
String formatMegabytes(int bytes) => '${math.max(1, (bytes / (1024 * 1024)).round())} MB';

/// What the engine tile says about the current network.
String networkLabel(String? path, int? bytes) {
  if (path == null) return 'Built-in light network';
  return bytes == null ? 'Full network' : 'Full network (${formatMegabytes(bytes)})';
}

/// Whether the SHA-256 of [file] starts with [prefix] (hex, any case).
Future<bool> fileHashMatches(File file, String prefix) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().startsWith(prefix.toLowerCase());
}

enum NetworkStatus { idle, checking, downloading, verifying, failed }

@immutable
class NetworkDownloadState {
  const NetworkDownloadState({
    this.status = NetworkStatus.idle,
    this.receivedBytes = 0,
    this.totalBytes,
    this.error,
  });

  final NetworkStatus status;
  final int receivedBytes;
  final int? totalBytes;

  /// Set when [status] is [NetworkStatus.failed].
  final String? error;

  bool get isBusy =>
      status == NetworkStatus.checking ||
      status == NetworkStatus.downloading ||
      status == NetworkStatus.verifying;

  /// 0 to 1 while the size is known, otherwise `null`.
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkDownloadState &&
      other.status == status &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, receivedBytes, totalBytes, error);
}

typedef DirectoryProvider = Future<Directory> Function();

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// The expected hash prefix. Tests override this.
final networkHashPrefixProvider = Provider<String>((ref) => networkHashPrefix);

/// Where the network file is kept. Tests override this.
final networkDirectoryProvider = Provider<DirectoryProvider>(
  (ref) => getApplicationSupportDirectory,
);

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Downloads the full network, checks it, and switches the engine to it.
class NetworkDownloadController extends Notifier<NetworkDownloadState> {
  static const Duration _timeout = Duration(seconds: 30);
  static const int _reportEveryBytes = 256 * 1024;

  bool _cancelRequested = false;

  http.Client get _client => ref.read(httpClientProvider);

  void _log(String message) => ref.read(reportingProvider)?.log.info(message);

  @override
  NetworkDownloadState build() => const NetworkDownloadState();

  /// Asks the server how big the file is. Returns `null` and sets a failed
  /// state when no server answers.
  Future<int?> checkSize() async {
    if (state.isBusy) return null;
    state = const NetworkDownloadState(status: NetworkStatus.checking);
    for (final url in networkUrls) {
      try {
        final response = await _client.head(Uri.parse(url)).timeout(_timeout);
        final length = int.tryParse(response.headers['content-length'] ?? '') ??
            (response.contentLength ?? 0);
        if (response.statusCode == 200 && length > 0) {
          state = const NetworkDownloadState();
          return length;
        }
      } catch (_) {
        // Try the next address.
      }
    }
    _log('Network size check failed');
    state = const NetworkDownloadState(
      status: NetworkStatus.failed,
      error: 'Could not reach the download server. Check your internet '
          'connection and try again. The built-in network stays in use.',
    );
    return null;
  }

  /// Downloads, verifies and installs the network. Returns whether the engine
  /// now uses it. On failure or cancel the built-in network stays.
  Future<bool> download() async {
    if (state.isBusy) return false;
    _cancelRequested = false;
    state = const NetworkDownloadState(status: NetworkStatus.downloading);
    _log('Network download started');

    File? part;
    String? lastError;
    try {
      final directory = await ref.read(networkDirectoryProvider)();
      await directory.create(recursive: true);
      part = File(p.join(directory.path, '$networkFileName.part'));
      for (final url in networkUrls) {
        if (_cancelRequested) break;
        try {
          await _fetch(url, part);
          state = NetworkDownloadState(
            status: NetworkStatus.verifying,
            receivedBytes: state.receivedBytes,
            totalBytes: state.totalBytes,
          );
          if (!await fileHashMatches(part, ref.read(networkHashPrefixProvider))) {
            lastError = 'The downloaded file did not pass the check and was '
                'deleted. Please try again.';
            _log('Network checksum mismatch from the server');
            await _deleteQuietly(part);
            continue;
          }
          final target = File(p.join(directory.path, networkFileName));
          if (await target.exists()) await target.delete();
          await part.rename(target.path);
          await ref.read(settingsProvider.notifier).setEngineNetworkPath(target.path);
          state = const NetworkDownloadState();
          _log('Full network installed');
          return true;
        } on _Cancelled {
          break;
        } catch (error) {
          lastError = _describe(error);
          _log('Network download failed: ${error.runtimeType}');
          await _deleteQuietly(part);
        }
      }
    } catch (error) {
      lastError = _describe(error);
      _log('Network download failed: ${error.runtimeType}');
    }
    if (part != null) await _deleteQuietly(part);
    if (_cancelRequested) {
      _log('Network download cancelled');
      state = const NetworkDownloadState();
    } else {
      state = NetworkDownloadState(
        status: NetworkStatus.failed,
        error: '${lastError ?? 'The download failed.'} The built-in network stays in use.',
      );
    }
    return false;
  }

  Future<void> _fetch(String url, File part) async {
    final response = await _client.send(http.Request('GET', Uri.parse(url))).timeout(_timeout);
    if (response.statusCode != 200) {
      throw HttpException('Server answered ${response.statusCode}');
    }
    final total = response.contentLength;
    state = NetworkDownloadState(status: NetworkStatus.downloading, totalBytes: total);
    final sink = part.openWrite();
    var received = 0;
    var reported = 0;
    try {
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (_cancelRequested) throw const _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        if (received - reported >= _reportEveryBytes) {
          reported = received;
          state = NetworkDownloadState(
            status: NetworkStatus.downloading,
            receivedBytes: received,
            totalBytes: total,
          );
        }
      }
    } finally {
      await sink.close();
    }
    if (total != null && received != total) {
      throw const HttpException('The download ended early');
    }
    state = NetworkDownloadState(
      status: NetworkStatus.downloading,
      receivedBytes: received,
      totalBytes: total ?? received,
    );
  }

  /// Stops a running download. The partial file is deleted.
  void cancel() {
    if (state.status == NetworkStatus.downloading) _cancelRequested = true;
  }

  /// Clears a failed state, so the message goes away.
  void dismissError() {
    if (state.status == NetworkStatus.failed) state = const NetworkDownloadState();
  }

  /// Goes back to the built-in network and deletes the downloaded file.
  Future<void> useBuiltIn() async {
    final path = ref.read(settingsProvider).engineNetworkPath;
    await ref.read(settingsProvider.notifier).setEngineNetworkPath(null);
    _log('Switched to the built-in network');
    if (path != null) await _deleteQuietly(File(path));
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _describe(Object error) {
    if (error is TimeoutException) return 'The connection timed out.';
    if (error is SocketException) return 'No internet connection.';
    if (error is HttpException) return '${error.message}.';
    if (error is http.ClientException) return 'The download could not be completed.';
    if (error is FileSystemException) return 'Could not save the file. Is the phone storage full?';
    return 'The download failed.';
  }
}

final networkDownloadProvider =
    NotifierProvider<NetworkDownloadController, NetworkDownloadState>(
  NetworkDownloadController.new,
);

/// Size of the installed full network in bytes, or `null` when the built-in
/// network is in use (or the file is gone).
final installedNetworkSizeProvider = FutureProvider.autoDispose<int?>((ref) async {
  final path = ref.watch(settingsProvider.select((s) => s.engineNetworkPath));
  if (path == null) return null;
  try {
    return await File(path).length();
  } catch (_) {
    return null;
  }
});
