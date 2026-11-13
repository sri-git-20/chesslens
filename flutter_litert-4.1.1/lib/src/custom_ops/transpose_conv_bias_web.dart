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

/// Loads and provides access to the Convolution2DTransposeBias custom op.
///
/// On web, custom native ops are not supported. This is a no-op stub.
class TransposeConvBiasOp {
  /// Returns whether the custom op has been successfully loaded.
  /// Always false on web.
  static bool get isLoaded => false;

  /// Returns whether the custom op has been registered with an interpreter options.
  /// Always false on web.
  static bool get isRegistered => false;

  /// Loads the custom ops library.
  /// On web, this is a no-op.
  static void loadLibrary() {
    // No-op on web: native custom ops are not available.
  }

  /// Registers the Convolution2DTransposeBias custom op with the given interpreter options.
  /// On web, this is a no-op.
  static void registerWithOptions(Object options) {
    // No-op on web: native custom ops are not available.
  }
}
