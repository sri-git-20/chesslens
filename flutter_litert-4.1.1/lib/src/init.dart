export 'unsupported/init.dart'
    if (dart.library.io) 'native/init.dart'
    if (dart.library.js_interop) 'web/web_init.dart';
