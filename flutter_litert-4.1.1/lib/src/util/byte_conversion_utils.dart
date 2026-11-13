export 'byte_conversion_utils_unsupported.dart'
    if (dart.library.io) 'byte_conversion_utils_native.dart'
    if (dart.library.js_interop) 'byte_conversion_utils_web.dart';
