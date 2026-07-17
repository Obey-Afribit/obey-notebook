import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_capture_stub.dart'
    if (dart.library.html) 'camera_capture_web.dart' as impl;

/// Opens a live webcam capture UI and returns the captured JPEG bytes, or null
/// if the user cancelled or no camera is available.
///
/// This exists for the **web** build: desktop browsers don't open a camera from
/// a file input, so `image_picker`'s camera source silently falls back to a file
/// dialog. On non-web platforms this returns null (mobile uses the native camera
/// through image_picker instead), so callers only reach it when `kIsWeb`.
Future<Uint8List?> captureFromWebcam(BuildContext context) =>
    impl.captureFromWebcam(context);
