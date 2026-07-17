import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Non-web fallback: there is no browser webcam here, so this is never the path
/// used to capture (mobile uses the native camera via image_picker).
Future<Uint8List?> captureFromWebcam(BuildContext context) async => null;
