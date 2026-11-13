import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chesslens/src/engine/network_download.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List goodData = Uint8List.fromList(List.generate(600 * 1024, (i) => i % 251));
final String goodPrefix = sha256.convert(goodData).toString().substring(0, 12);
final Uint8List badData = Uint8List.fromList(List.filled(1000, 7));

void main() {
  late Directory temp;
  late ProviderContainer container;
  late SharedPreferences prefs;

  Future<ProviderContainer> makeContainer(http.Client client, {String? prefix}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        httpClientProvider.overrideWithValue(client),
        networkHashPrefixProvider.overrideWithValue(prefix ?? goodPrefix),
        networkDirectoryProvider.overrideWithValue(() async => temp),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => temp = Directory.systemTemp.createTempSync('chesslens_nn_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('helpers', () {
    test('formatMegabytes rounds and never says 0', () {
      expect(formatMegabytes(40 * 1024 * 1024 + 300000), '40 MB');
      expect(formatMegabytes(10), '1 MB');
    });

    test('networkLabel', () {
      expect(networkLabel(null, null), 'Built-in light network');
      expect(networkLabel('/x', 41 * 1024 * 1024), 'Full network (41 MB)');
      expect(networkLabel('/x', null), 'Full network');
    });

    test('fileHashMatches compares the start of the SHA-256', () async {
      final file = File('${temp.path}/a.bin')..writeAsBytesSync(goodData);
      expect(await fileHashMatches(file, goodPrefix), isTrue);
      expect(await fileHashMatches(file, goodPrefix.toUpperCase()), isTrue);
      expect(await fileHashMatches(file, '000000000000'), isFalse);
    });

    test('the expected file name carries the expected hash prefix', () {
      expect(networkFileName, 'nn-$networkHashPrefix.nnue');
      expect(networkUrls.first, startsWith('https://tests.stockfishchess.org/'));
      expect(networkUrls.last, contains('github.com/official-stockfish/networks'));
    });
  });

  group('checkSize', () {
    test('reads the size from content-length', () async {
      final client = MockClient((request) async {
        expect(request.method, 'HEAD');
        return http.Response('', 200, headers: {'content-length': '41943040'});
      });
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).checkSize(), 41943040);
      expect(c.read(networkDownloadProvider).status, NetworkStatus.idle);
    });

    test('falls back to the second address', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add(request.url.host);
        if (request.url.host == 'tests.stockfishchess.org') {
          return http.Response('', 503);
        }
        return http.Response('', 200, headers: {'content-length': '1234'});
      });
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).checkSize(), 1234);
      expect(seen, ['tests.stockfishchess.org', 'github.com']);
    });

    test('fails with a clear message when nothing answers', () async {
      final client = MockClient((request) async => throw const SocketException('offline'));
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).checkSize(), isNull);
      final state = c.read(networkDownloadProvider);
      expect(state.status, NetworkStatus.failed);
      expect(state.error, contains('Could not reach'));
      c.read(networkDownloadProvider.notifier).dismissError();
      expect(c.read(networkDownloadProvider).status, NetworkStatus.idle);
    });
  });

  group('download', () {
    test('verifies, installs and switches the engine', () async {
      final client = MockClient.streaming((request, body) async {
        expect(request.method, 'GET');
        final chunks = <List<int>>[
          for (var i = 0; i < goodData.length; i += 100000)
            goodData.sublist(i, i + 100000 > goodData.length ? goodData.length : i + 100000),
        ];
        return http.StreamedResponse(
          Stream.fromIterable(chunks),
          200,
          contentLength: goodData.length,
        );
      });
      final c = await makeContainer(client);
      final statuses = <NetworkStatus>[];
      c.listen(networkDownloadProvider, (_, next) {
        if (statuses.isEmpty || statuses.last != next.status) statuses.add(next.status);
      });

      expect(await c.read(networkDownloadProvider.notifier).download(), isTrue);

      final path = c.read(settingsProvider).engineNetworkPath;
      expect(path, '${temp.path}/$networkFileName');
      expect(File(path!).readAsBytesSync(), goodData);
      expect(File('${temp.path}/$networkFileName.part').existsSync(), isFalse);
      expect(prefs.getString(SettingsController.engineNetworkPathKey), path);
      expect(statuses, [
        NetworkStatus.downloading,
        NetworkStatus.verifying,
        NetworkStatus.idle,
      ]);
    });

    test('uses the second address when the first one fails', () async {
      final client = MockClient.streaming((request, body) async {
        if (request.url.host == 'tests.stockfishchess.org') {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          Stream.value(goodData),
          200,
          contentLength: goodData.length,
        );
      });
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).download(), isTrue);
      expect(c.read(settingsProvider).engineNetworkPath, isNotNull);
    });

    test('a file with the wrong hash is deleted and the light network stays', () async {
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream.value(badData),
          200,
          contentLength: badData.length,
        );
      });
      final c = await makeContainer(client);

      expect(await c.read(networkDownloadProvider.notifier).download(), isFalse);

      final state = c.read(networkDownloadProvider);
      expect(state.status, NetworkStatus.failed);
      expect(state.error, contains('did not pass the check'));
      expect(state.error, contains('built-in network stays'));
      expect(c.read(settingsProvider).engineNetworkPath, isNull);
      expect(temp.listSync(), isEmpty);
    });

    test('a download that ends early fails', () async {
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream.value(goodData.sublist(0, 1000)),
          200,
          contentLength: goodData.length,
        );
      });
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).download(), isFalse);
      expect(c.read(networkDownloadProvider).status, NetworkStatus.failed);
      expect(c.read(settingsProvider).engineNetworkPath, isNull);
      expect(temp.listSync(), isEmpty);
    });

    test('no internet gives a clear message', () async {
      final client = MockClient.streaming(
        (request, body) async => throw const SocketException('offline'),
      );
      final c = await makeContainer(client);
      expect(await c.read(networkDownloadProvider.notifier).download(), isFalse);
      expect(c.read(networkDownloadProvider).error, contains('No internet connection'));
    });

    test('cancel stops the download and removes the partial file', () async {
      final controller = StreamController<List<int>>();
      final client = MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          controller.stream,
          200,
          contentLength: goodData.length,
        );
      });
      final c = await makeContainer(client);
      final notifier = c.read(networkDownloadProvider.notifier);

      final result = notifier.download();
      controller.add(goodData.sublist(0, 300 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(networkDownloadProvider).status, NetworkStatus.downloading);
      expect(c.read(networkDownloadProvider).receivedBytes, greaterThan(0));

      notifier.cancel();
      controller.add(goodData.sublist(300 * 1024, 400 * 1024));
      unawaited(controller.close());

      expect(await result, isFalse);
      expect(c.read(networkDownloadProvider).status, NetworkStatus.idle);
      expect(c.read(settingsProvider).engineNetworkPath, isNull);
      expect(temp.listSync(), isEmpty);
    });

    test('progress is the share of bytes received', () {
      const state = NetworkDownloadState(
        status: NetworkStatus.downloading,
        receivedBytes: 25,
        totalBytes: 100,
      );
      expect(state.progress, 0.25);
      expect(const NetworkDownloadState().progress, isNull);
    });
  });

  test('useBuiltIn deletes the file and clears the setting', () async {
    final c = await makeContainer(MockClient((request) async => http.Response('', 500)));
    final file = File('${temp.path}/$networkFileName')..writeAsBytesSync(goodData);
    await c.read(settingsProvider.notifier).setEngineNetworkPath(file.path);

    await c.read(networkDownloadProvider.notifier).useBuiltIn();

    expect(c.read(settingsProvider).engineNetworkPath, isNull);
    expect(prefs.containsKey(SettingsController.engineNetworkPathKey), isFalse);
    expect(file.existsSync(), isFalse);
  });
}
