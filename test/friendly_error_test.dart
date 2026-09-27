import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_notebook/core/friendly_error.dart';
import 'package:universal_notebook/services/storage_service.dart';

void main() {
  group('friendlyError', () {
    test('network failures become a connection message', () {
      final String message = friendlyError(
        Exception(
          "ClientException with SocketException: Failed host lookup: 'x.supabase.co'",
        ),
      );
      expect(message, contains("Can't reach the server"));
      expect(message, isNot(contains('SocketException')));
    });

    test('wrong password', () {
      expect(
        friendlyError(const AuthException('Invalid login credentials',
            code: 'invalid_credentials')),
        contains("don't match"),
      );
    });

    test('existing account', () {
      expect(
        friendlyError(const AuthException('User already registered',
            code: 'user_already_exists')),
        contains('already exists'),
      );
    });

    test('rate limiting', () {
      expect(
        friendlyError(const AuthException('slow down', statusCode: '429')),
        contains('Too many attempts'),
      );
    });

    test('unknown errors never leak internals', () {
      expect(friendlyError(Exception('NullThrownError at 0xdeadbeef')),
          'Something went wrong. Please try again.');
    });
  });

  group('StorageService.storagePathFromUrl', () {
    test('extracts the object path from a public URL', () {
      expect(
        StorageService.storagePathFromUrl(
          'https://ref.supabase.co/storage/v1/object/public/note-images/u1/n1/abc.png',
        ),
        'u1/n1/abc.png',
      );
    });

    test('ignores URLs from elsewhere', () {
      expect(StorageService.storagePathFromUrl('https://example.com/a.png'), isNull);
    });
  });
}
