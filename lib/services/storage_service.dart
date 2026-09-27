import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Uploads note images to Supabase Storage and returns public URLs.
///
/// Objects are keyed as `<userId>/<noteId>/<uuid>.<ext>` inside the public
/// `note-images` bucket. The storage RLS policy scopes writes to the owner
/// (first path segment must equal `auth.uid()`), while reads stay public — that
/// is what lets the Markdown preview load an image straight from its URL with
/// no auth token. Keeping images in Storage (rather than base64 inside the note
/// body) keeps the notes table and every sync payload small.
class StorageService {
  const StorageService();

  static const String bucketId = 'note-images';

  Future<String> uploadNoteImage({
    required String userId,
    required String noteId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final String ext = _normalizeExtension(fileExtension);
    final String path = '$userId/$noteId/${const Uuid().v4()}.$ext';
    final SupabaseClient client = Supabase.instance.client;

    await client.storage.from(bucketId).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(ext),
            upsert: false,
          ),
        );

    return client.storage.from(bucketId).getPublicUrl(path);
  }

  /// Deletes the stored objects behind [urls]. URLs that don't point into this
  /// bucket are ignored. Failures are swallowed: an orphaned image costs a few
  /// kilobytes, while a thrown error here would block the user's action.
  Future<void> deleteImagesByUrl(Iterable<String> urls) async {
    final List<String> paths = urls
        .map(storagePathFromUrl)
        .whereType<String>()
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }
    try {
      await Supabase.instance.client.storage.from(bucketId).remove(paths);
    } catch (_) {
      // Best effort.
    }
  }

  /// `.../storage/v1/object/public/note-images/<path>` -> `<path>`.
  static String? storagePathFromUrl(String url) {
    const String marker = '/storage/v1/object/public/$bucketId/';
    final int index = url.indexOf(marker);
    if (index == -1) {
      return null;
    }
    final String path = url.substring(index + marker.length).split('?').first;
    return path.isEmpty ? null : Uri.decodeComponent(path);
  }

  String _normalizeExtension(String raw) {
    final String cleaned = raw.replaceAll('.', '').toLowerCase().trim();
    const Set<String> allowed = <String>{
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
    };
    return allowed.contains(cleaned) ? cleaned : 'jpg';
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
