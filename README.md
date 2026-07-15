# Universal Notebook

An offline-first notes app for **Android, Windows, and the web**, built with
Flutter. Notes live on-device first (instant, works with no network) and sync to
the cloud when configured.

## Architecture

- **UI / state:** Flutter + `provider`. `NotebookController` orchestrates all app
  state; feature screens live under `lib/features/`.
- **Local store:** Hive (`lib/services/local_store_service.dart`) — the source of
  truth on every device. Works on Android, Windows, and web (IndexedDB).
- **Cloud backend:** Supabase (Postgres + Auth). Pure-Dart SDK, so it builds
  cleanly on Windows and web with no native C++ SDK.
- **Sync:** a local mutation queue is pushed to Supabase with a keep-both
  conflict strategy (`lib/services/sync_service.dart`).

Notes and folders are stored in Postgres as `{ id, owner_id, revision,
updated_at, data jsonb }`, where `data` is the same map the app persists locally.
Row-Level Security scopes every row to its owner. See `supabase/schema.sql`.

## Running

The app runs fully offline with **no configuration** (local-only mode):

```
flutter run -d windows        # or: -d chrome, or an Android device
```

To enable cloud auth + sync, pass your Supabase project values (never commit
these):

```
flutter run -d windows ^
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

AI features (optional) are enabled by also passing:

```
  --dart-define=ANTHROPIC_API_KEY=YOUR_KEY
```

### Cloud setup (one time)

1. Create a project at supabase.com.
2. Open the SQL editor and run `supabase/schema.sql`.
3. Copy the project URL and anon/publishable key into the `--dart-define`
   flags above (or a `--dart-define-from-file` JSON).

## Features

Local-first notes with autosave, nested folders (with biometric lock), search
and filters, templates, TXT/PDF export, share, reminders, version history,
pin / archive / trash, quick capture, and a theme system. Speech-to-text is
available on supported platforms; OCR returns in the mobile build.

## Project layout

- `lib/core/` — models, theme, `app_config.dart` (build-time config).
- `lib/services/` — auth, local store, sync, templates, reminders, share, etc.
- `lib/features/` — auth, home, notes, templates, settings screens.
- `lib/state/notebook_controller.dart` — central app state.
- `supabase/schema.sql` — cloud schema + RLS + account-deletion function.
- `assets/` — theme packs and starter templates.
