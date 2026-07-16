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

AI features (optional, Claude-powered) are enabled by also passing:

```
  --dart-define=ANTHROPIC_API_KEY=YOUR_KEY
```

The key is read at build time. It is fine for a personal build with your own
key, but a published app should proxy AI calls through a backend (e.g. a
Supabase Edge Function) rather than shipping the key to clients.

### Cloud setup (one time)

1. Create a project at supabase.com.
2. Open the SQL editor and run `supabase/schema.sql`.
3. Copy the project URL and anon/publishable key into the `--dart-define`
   flags above (or a `--dart-define-from-file` JSON).

## Features

Local-first notes with a **Markdown editor** (formatting toolbar + live split
preview), autosave, nested folders (with biometric lock), search and filters,
templates, TXT/PDF export, share, reminders, version history, pin / archive /
trash, quick capture, and a **theme system** (8 accent colors × light/dark/system
mode). **AI assist** (Claude) can summarize a note, clean up rough writing, and
suggest tags when a key is configured. Speech-to-text is available on supported
platforms (including Windows via SAPI); OCR returns in the mobile build.

Runs on **Windows, Android, and the web** (installable PWA). The web build works
with the same codebase; file exports and `dart:io` usage are behind conditional
imports so the web target compiles cleanly.

## Project layout

- `lib/core/` — models, theme, `app_config.dart` (build-time config).
- `lib/services/` — auth, local store, sync, templates, reminders, share, etc.
- `lib/features/` — auth, home, notes, templates, settings screens.
- `lib/state/notebook_controller.dart` — central app state.
- `supabase/schema.sql` — cloud schema + RLS + account-deletion function.
- `assets/` — theme packs and starter templates.
