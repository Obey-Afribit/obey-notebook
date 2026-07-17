// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Live webcam capture for the web build using `getUserMedia`.
///
/// Streams the camera into a `<video>` element embedded via [HtmlElementView],
/// then draws the current frame to a canvas and returns it as JPEG bytes. The
/// camera track is always stopped before returning so the webcam light goes off.
Future<Uint8List?> captureFromWebcam(BuildContext context) async {
  final html.MediaDevices? devices = html.window.navigator.mediaDevices;
  if (devices == null) {
    return null;
  }

  final html.MediaStream stream;
  try {
    stream = await devices.getUserMedia(<String, dynamic>{
      'video': true,
      'audio': false,
    });
  } catch (_) {
    return null; // permission denied, or no camera
  }

  final html.VideoElement video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..srcObject = stream
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover';
  video.setAttribute('playsinline', 'true');

  final String viewType =
      'webcam-view-${DateTime.now().microsecondsSinceEpoch}';
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int _) => video,
  );

  Uint8List? captured;

  if (context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: HtmlElementView(viewType: viewType),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        captured = _grabFrame(video);
                        Navigator.of(dialogContext).pop();
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  for (final html.MediaStreamTrack track in stream.getTracks()) {
    track.stop();
  }

  return captured;
}

Uint8List? _grabFrame(html.VideoElement video) {
  final int width = video.videoWidth;
  final int height = video.videoHeight;
  if (width == 0 || height == 0) {
    return null;
  }
  final html.CanvasElement canvas =
      html.CanvasElement(width: width, height: height);
  canvas.context2D.drawImage(video, 0, 0);
  final String dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
  final int comma = dataUrl.indexOf(',');
  if (comma == -1) {
    return null;
  }
  return base64Decode(dataUrl.substring(comma + 1));
}
