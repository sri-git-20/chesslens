import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registration for flutter_litert.
///
/// The actual web implementation is handled through conditional imports
/// (dart.library.js_interop). This class just registers the plugin
/// with Flutter's web plugin system.
class FlutterLitertWeb {
  static void registerWith(Registrar registrar) {
    // No-op, flutter_litert uses conditional imports, not platform channels.
  }
}
