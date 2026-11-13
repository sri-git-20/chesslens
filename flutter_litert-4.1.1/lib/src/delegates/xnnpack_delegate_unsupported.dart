/*
 * Copyright 2023 The TensorFlow Authors. All Rights Reserved.
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

/// XNNPack Delegate (unsupported platform)
class XNNPackDelegate {
  XNNPackDelegate({XNNPackDelegateOptions? options}) {
    throw UnsupportedError('XNNPackDelegate is not supported on this platform');
  }

  void delete() {
    throw UnsupportedError('XNNPackDelegate is not supported on this platform');
  }
}

/// XNNPackDelegate Options (unsupported platform)
class XNNPackDelegateOptions {
  XNNPackDelegateOptions({
    int numThreads = 1,
    int flags = 0,
    String? weightCacheFilePath,
  }) {
    throw UnsupportedError(
      'XNNPackDelegateOptions is not supported on this platform',
    );
  }

  void delete() {
    throw UnsupportedError(
      'XNNPackDelegateOptions is not supported on this platform',
    );
  }
}
