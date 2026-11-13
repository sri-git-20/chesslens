export 'metal_delegate_unsupported.dart'
    if (dart.library.io) 'metal_delegate_native.dart'
    if (dart.library.js_interop) 'metal_delegate_web.dart';
