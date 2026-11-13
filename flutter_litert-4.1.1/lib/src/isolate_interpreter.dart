export 'unsupported/isolate_interpreter.dart'
    if (dart.library.io) 'native/isolate_interpreter.dart'
    if (dart.library.js_interop) 'web/isolate_interpreter.dart';
