import 'dart:async';
import 'package:web/web.dart' as web;

/// Loads JavaScript scripts by injecting <script> tags into the document head.
Future<void> loadScript(List<String> urls) async {
  final head = web.document.querySelector('head')!;

  for (final url in urls) {
    final scriptTag = web.HTMLScriptElement()
      ..src = url
      ..type = 'application/javascript'
      ..async = true;
    head.append(scriptTag);

    final loadEvent = scriptTag.onLoad.first;
    final errorEvent = scriptTag.onError.first;

    final success = await _waitForFirst(loadEvent, errorEvent);
    if (!success) {
      throw Exception('Failed to load script: $url');
    }
  }
}

Future<bool> _waitForFirst(
  Future<web.Event> onLoad,
  Future<web.Event> onError,
) {
  final completer = Completer<bool>();
  onLoad.then((value) => completer.complete(true));
  onError.then((value) => completer.complete(false));
  return completer.future;
}
