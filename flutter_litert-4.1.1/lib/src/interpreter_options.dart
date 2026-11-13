export 'unsupported/interpreter_options.dart'
    if (dart.library.io) 'native/interpreter_options.dart'
    if (dart.library.js_interop) 'web/interpreter_options.dart';
