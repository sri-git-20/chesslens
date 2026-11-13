export 'coreml_delegate_unsupported.dart'
    if (dart.library.io) 'coreml_delegate_native.dart'
    if (dart.library.js_interop) 'coreml_delegate_web.dart';
