/*
 * Copyright 2025 flutter_litert authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *             http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../bindings/bindings.dart';
import '../bindings/tensorflow_lite_bindings_generated.dart';
import '../delegates/delegate_library_loader.dart';

/// Loads and provides access to the Convolution2DTransposeBias custom op.
///
/// This custom op is required for MediaPipe models like Selfie Segmentation.
class TransposeConvBiasOp {
  static DynamicLibrary? _customOpsLib;
  static Pointer<TfLiteRegistration>? _registration;
  static bool _isRegistered = false;

  /// Persistent native string for the op name: must outlive all interpreters
  /// because TfLiteInterpreterOptionsAddCustomOp stores the pointer, not a copy.
  static Pointer<Char>? _opName;

  /// Returns whether the custom op has been successfully loaded.
  static bool get isLoaded => _registration != null;

  /// Returns whether the custom op has been registered with an interpreter options.
  static bool get isRegistered => _isRegistered;

  /// Loads the custom ops library.
  ///
  /// This is called automatically when needed, but can be called early
  /// to catch loading errors.
  static void loadLibrary() {
    if (_customOpsLib != null) return;

    final attempted = <String>[];
    _customOpsLib = _loadCustomOpsLibrary(attempted);
    if (_customOpsLib == null) {
      throw UnsupportedError(
        'Failed to load custom ops library.\n'
        'Attempted paths:\n'
        '${attempted.map((p) => '  - $p').join('\n')}',
      );
    }

    // Get the registration function
    final registerFn = _customOpsLib!
        .lookupFunction<
          Pointer<TfLiteRegistration> Function(),
          Pointer<TfLiteRegistration> Function()
        >('TfLiteFlutter_RegisterConvolution2DTransposeBias');

    _registration = registerFn();
  }

  /// Registers the Convolution2DTransposeBias custom op with the given interpreter options.
  ///
  /// Call this before creating an interpreter for models that use this op.
  static void registerWithOptions(Pointer<TfLiteInterpreterOptions> options) {
    if (_registration == null) {
      loadLibrary();
    }

    if (_registration == null) {
      throw StateError('Custom op registration not available');
    }

    _opName ??= 'Convolution2DTransposeBias'.toNativeUtf8().cast<Char>();
    tfliteBinding.TfLiteInterpreterOptionsAddCustomOp(
      options,
      _opName!,
      _registration!,
      1, // min_version
      1, // max_version
    );

    _isRegistered = true;
  }

  /// Attempts to load the custom ops library from various locations.
  /// Populates [outAttemptedPaths] (if provided) with tried paths for desktop
  /// platforms; callers can include them in error messages.
  static DynamicLibrary? _loadCustomOpsLibrary([
    List<String>? outAttemptedPaths,
  ]) {
    // iOS: Custom ops are statically linked into the app via CocoaPods.
    if (Platform.isIOS) {
      try {
        return DynamicLibrary.process();
      } catch (_) {
        try {
          return DynamicLibrary.executable();
        } catch (_) {
          return null;
        }
      }
    }

    // Android: Custom ops are built as a separate .so via CMake.
    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open('libtflite_custom_ops.so');
      } catch (_) {
        return null;
      }
    }

    String libName;
    if (Platform.isMacOS) {
      libName = 'libtflite_custom_ops.dylib';
    } else if (Platform.isLinux) {
      libName = 'libtflite_custom_ops.so';
    } else if (Platform.isWindows) {
      libName = 'tflite_custom_ops.dll';
    } else {
      return null;
    }

    // Build the full ordered search path list for this desktop platform.
    final List<String> paths;
    if (Platform.isMacOS) {
      final appBundle = Directory(Platform.resolvedExecutable).parent.parent;
      paths = [
        ...delegateBundlePaths(libName),
        '${appBundle.path}/Frameworks/$libName',
        '${Directory.current.path}/macos/$libName',
      ];
    } else if (Platform.isLinux) {
      paths = [
        '${Directory(Platform.resolvedExecutable).parent.path}/lib/$libName',
      ];
    } else {
      paths = [
        '${Directory(Platform.resolvedExecutable).parent.path}/$libName',
      ];
    }

    final attempted = outAttemptedPaths ?? <String>[];
    return probeLibraryPaths(
      envVar: 'TFLITE_CUSTOM_OPS_PATH',
      paths: paths,
      attemptedPaths: attempted,
    );
  }
}
