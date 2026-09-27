import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;
import 'package:uuid/uuid.dart';

import '../core/friendly_error.dart';
import '../core/markdown_tools.dart';
import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/template_item.dart';
import '../core/theme/theme_controller.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/local_store_service.dart';
import '../services/privacy_lock_service.dart';
import '../services/reminder_service.dart';
import '../services/share_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/template_service.dart';

/// Which slice of the notebook is on screen.
enum NotebookView { all, pinned, reminders, archive, trash, folder, tag }

enum NoteSort {
  edited('Last edited'),
  created('Date created'),
  title('Title');

  const NoteSort(this.label);
  final String label;
}

enum NoteLayout { grid, list }

/// Cloud sync status shown in the UI.
enum SyncState { localOnly, idle, syncing, offline, error }

class NotebookController extends ChangeNotifier {
  NotebookController({
    required AuthService authService,
    required LocalStoreService localStoreService,
    required SyncService syncService,
    required TemplateService templateService,
    required ThemeController themeController,
    required SpeechService speechService,
    required ReminderService reminderService,
    required ShareService shareService,
    required PrivacyLockService privacyLockService,
    required AiService aiService,
    required StorageService storageService,
  })  : _authService = authService,
        _localStore = localStoreService,
        _syncService = syncService,
        _templateService = templateService,
        _themeController = themeController,
        _speechService = speechService,
        _reminderService = reminderService,
        _shareService = shareService,
        _privacyLockService = privacyLockService,
        _aiService = aiService,
        _storageService = storageService;

  final AuthService _authService;
  final LocalStoreService _localStore;
  final SyncService _syncService;
  final TemplateService _templateService;
  final ThemeController _themeController;
  final SpeechService _speechService;
  final ReminderService _reminderService;
  final ShareService _shareService;
  final PrivacyLockService _privacyLockService;
  final AiService _aiService;
  final StorageService _storageService;

  final Uuid _uuid = const Uuid();

  static const Duration _trashRetention = Duration(days: 30);

  StreamSubscription<AuthState>? _authSubscription;
  AppLifecycleListener? _lifecycle;
  Timer? _syncTimer;
  Timer? _pushDebounce;
  Timer? _pullDebounce;
  Timer? _reminderTimer;

  // ---- session ---------------------------------------------------------------
  bool _isBootstrapping = true;
  bool _isBusy = false;
  bool _isSignedIn = false;
  bool _isVerified = false;
  bool _cloudConfigured = false;
  bool _staySignedIn = true;
  bool _lockSupported = false;
  bool _speechReady = false;
  bool _passwordRecovery = false;
  String? _sessionStartedFor;
  String? _error;
  String? _notice;

  // ---- navigation & display ---------------------------------------------------
  String _searchQuery = '';
  NotebookView _view = NotebookView.all;
  String? _selectedFolderId;
  String? _selectedTag;
  NoteSort _sort = NoteSort.edited;
  NoteLayout _layout = NoteLayout.grid;

  // ---- data -------------------------------------------------------------------
  List<NoteItem> _notes = <NoteItem>[];
  List<FolderItem> _folders = <FolderItem>[];
  List<TemplateItem> _templates = <TemplateItem>[];
  Set<String> _lockedFolderIds = <String>{};
  final Set<String> _unlockedFolderIds = <String>{};

  // ---- selection --------------------------------------------------------------
  bool _selectionMode = false;
  final Set<String> _selectedNoteIds = <String>{};

  // ---- sync -------------------------------------------------------------------
  SyncState _syncState = SyncState.localOnly;
  DateTime? _lastSyncedAt;
  DateTime? _lastPullAt;
  bool _syncRunning = false;
  bool _syncAgain = false;
  bool _syncAgainPull = false;
  int _pendingCount = 0;

  // ---- reminders --------------------------------------------------------------
  /// Reminders that came due while the app is open on a platform without
  /// native notifications (Windows, web). The home screen shows these.
  final ValueNotifier<List<NoteItem>> reminderAlerts =
      ValueNotifier<List<NoteItem>>(const <NoteItem>[]);
  Set<String> _firedReminderKeys = <String>{};

  // ===========================================================================
  // Getters
  // ===========================================================================

  bool get isBootstrapping => _isBootstrapping;
  bool get isBusy => _isBusy;
  bool get isSignedIn => _isSignedIn;
  bool get isVerified => _isVerified;
  bool get cloudConfigured => _cloudConfigured;
  bool get staySignedIn => _staySignedIn;
  bool get lockSupported => _lockSupported;
  bool get passwordRecoveryPending => _passwordRecovery;
  String? get cloudStatusMessage => _authService.initializationError;
  String? get error => _error;
  String? get notice => _notice;
  String? get accountEmail => _authService.currentEmail;

  String get searchQuery => _searchQuery;
  NotebookView get view => _view;
  String? get selectedFolderId => _selectedFolderId;
  String? get selectedTag => _selectedTag;
  NoteSort get sort => _sort;
  NoteLayout get layout => _layout;

  List<NoteItem> get notes => _notes;
  List<FolderItem> get folders => _folders;
  List<TemplateItem> get templates => _templates;
  Set<String> get lockedFolderIds => _lockedFolderIds;

  bool get selectionMode => _selectionMode;
  Set<String> get selectedNoteIds => _selectedNoteIds;
  int get selectedCount => _selectedNoteIds.length;
  bool isNoteSelected(String noteId) => _selectedNoteIds.contains(noteId);
  List<NoteItem> get selectedNotes => _notes
      .where((NoteItem note) => _selectedNoteIds.contains(note.id))
      .toList(growable: false);

  SyncState get syncState => _syncState;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get pendingChanges => _pendingCount;
  bool get liveSyncConnected => _syncService.realtimeConnected;

  bool get hasNotebookAccess =>
      _isSignedIn && (!_cloudConfigured || _isVerified);

  bool get aiAvailable => _aiService.isAvailable;

  bool get speechSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Inline images live in Supabase Storage, which needs a cloud session.
  bool get imagesSupported => _cloudConfigured && _isSignedIn;

  bool get nativeReminders => _reminderService.nativeSupported;

  NoteItem? getNoteById(String noteId) {
    for (final NoteItem note in _notes) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  FolderItem? folderById(String? id) {
    if (id == null) {
      return null;
    }
    for (final FolderItem folder in _folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }

  bool isFolderLocked(String folderId) =>
      _lockSupported && _lockedFolderIds.contains(folderId);

  bool _hiddenByLock(NoteItem note) =>
      isFolderLocked(note.folderId) &&
      !_unlockedFolderIds.contains(note.folderId);

  // ---- views ------------------------------------------------------------------

  String get viewTitle {
    switch (_view) {
      case NotebookView.all:
        return 'All notes';
      case NotebookView.pinned:
        return 'Pinned';
      case NotebookView.reminders:
        return 'Reminders';
      case NotebookView.archive:
        return 'Archive';
      case NotebookView.trash:
        return 'Trash';
      case NotebookView.folder:
        return folderById(_selectedFolderId)?.name ?? 'Folder';
      case NotebookView.tag:
        return '#${_selectedTag ?? ''}';
    }
  }

  bool _inView(NoteItem note, {required bool searching}) {
    switch (_view) {
      case NotebookView.all:
        // Searching from "All notes" also finds archived notes.
        return !note.isDeleted &&
            (searching || !note.isArchived) &&
            !_hiddenByLock(note);
      case NotebookView.pinned:
        return !note.isDeleted &&
            !note.isArchived &&
            note.isPinned &&
            !_hiddenByLock(note);
      case NotebookView.reminders:
        return !note.isDeleted &&
            note.reminderAt != null &&
            !_hiddenByLock(note);
      case NotebookView.archive:
        return note.isArchived && !note.isDeleted && !_hiddenByLock(note);
      case NotebookView.trash:
        return note.isDeleted;
      case NotebookView.folder:
        return !note.isDeleted &&
            !note.isArchived &&
            note.folderId == _selectedFolderId;
      case NotebookView.tag:
        return !note.isDeleted &&
            !note.isArchived &&
            note.tags.contains(_selectedTag) &&
            !_hiddenByLock(note);
    }
  }

  /// Notes for the current view, filtered by search and sorted. Pinned notes
  /// come first where pinning is meaningful.
  List<NoteItem> get visibleNotes {
    final String query = _searchQuery.trim().toLowerCase();
    final bool searching = query.isNotEmpty;

    final List<NoteItem> list = _notes.where((NoteItem note) {
      if (!_inView(note, searching: searching)) {
        return false;
      }
      if (!searching) {
        return true;
      }
      return note.title.toLowerCase().contains(query) ||
          note.body.toLowerCase().contains(query) ||
          note.tags.any((String tag) => tag.toLowerCase().contains(query));
    }).toList();

    list.sort(_compare);
    return list;
  }

  /// Whether the notes view splits into "Pinned" and "Others" sections.
  bool get showsPinnedSection =>
      _view == NotebookView.all ||
      _view == NotebookView.folder ||
      _view == NotebookView.tag;

  int _compare(NoteItem a, NoteItem b) {
    switch (_view) {
      case NotebookView.reminders:
        return a.reminderAt!.compareTo(b.reminderAt!);
      case NotebookView.trash:
        return (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt);
      default:
        break;
    }
    switch (_sort) {
      case NoteSort.edited:
        return b.updatedAt.compareTo(a.updatedAt);
      case NoteSort.created:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSort.title:
        final String at = a.displayTitle.toLowerCase();
        final String bt = b.displayTitle.toLowerCase();
        if (at.isEmpty != bt.isEmpty) {
          return at.isEmpty ? 1 : -1; // untitled last
        }
        return at.compareTo(bt);
    }
  }

  // ---- counts ---------------------------------------------------------------

  Iterable<NoteItem> get _live =>
      _notes.where((NoteItem n) => !n.isDeleted && !_hiddenByLock(n));

  int get allCount => _live.where((NoteItem n) => !n.isArchived).length;
  int get pinnedCount =>
      _live.where((NoteItem n) => !n.isArchived && n.isPinned).length;
  int get remindersCount =>
      _live.where((NoteItem n) => n.reminderAt != null).length;
  int get archiveCount => _live.where((NoteItem n) => n.isArchived).length;
  int get trashCount => _notes.where((NoteItem n) => n.isDeleted).length;

  int folderNoteCount(String folderId) => _notes
      .where((NoteItem n) =>
          !n.isDeleted && !n.isArchived && n.folderId == folderId)
      .length;

  /// Every tag in use, with how many live notes carry it, sorted by name.
  List<MapEntry<String, int>> get tagCounts {
    final Map<String, int> counts = <String, int>{};
    for (final NoteItem note in _live) {
      if (note.isArchived) {
        continue;
      }
      for (final String tag in note.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final List<MapEntry<String, int>> entries = counts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return entries;
  }

  List<NoteItem> get trashNotes =>
      _notes.where((NoteItem note) => note.isDeleted).toList(growable: false);

  /// Top-level folders first, then children, each level sorted by name.
  List<FolderItem> childFolders(String? parentId) {
    final List<FolderItem> list = _folders
        .where((FolderItem f) => f.parentId == parentId)
        .toList()
      ..sort((FolderItem a, FolderItem b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ===========================================================================
  // Start-up and lifecycle
  // ===========================================================================

  Future<void> initialize() async {
    _isBootstrapping = true;
    _error = null;
    notifyListeners();

    try {
      await _localStore.init();
      await _themeController.initialize();
      await _authService.initialize();
      await _reminderService.initialize();
      _lockSupported = await _privacyLockService.isSupported();

      _staySignedIn = _localStore.readStaySignedIn();
      _lockedFolderIds = _localStore.readLockedFolderIds();
      _firedReminderKeys = _localStore.readStringSet('fired_reminders');
      _sort = NoteSort.values.firstWhere(
        (NoteSort s) => s.name == _localStore.readSetting<String>('note_sort'),
        orElse: () => NoteSort.edited,
      );
      _layout = _localStore.readSetting<String>('note_layout') == 'list'
          ? NoteLayout.list
          : NoteLayout.grid;

      _cloudConfigured = _authService.isCloudReady;
      if (_cloudConfigured) {
        // "Stay signed in" off means every launch starts at the sign-in screen.
        if (_authService.isSignedIn && !_staySignedIn) {
          await _authService.signOut();
        }
        _isSignedIn = _authService.isSignedIn;
        _isVerified = _authService.isEmailVerified;
        _syncState = SyncState.idle;
      } else {
        final bool offline = _localStore.readOfflineAccessGranted();
        _isSignedIn = offline;
        _isVerified = offline;
        _syncState = SyncState.localOnly;
      }

      _authSubscription =
          _authService.authStateChanges().listen(_onAuthStateChanged);

      await _refreshData();
      await _purgeExpiredTrash();

      if (_isSignedIn) {
        if (_cloudConfigured) {
          // Show cached notes immediately; sync catches up in the background.
          unawaited(_ensureSessionStarted());
        } else {
          await _ensureInbox();
        }
      }

      _syncTimer = Timer.periodic(
        const Duration(seconds: 30),
        (Timer _) => _periodicSync(),
      );
      _startReminderWatcher();
      _lifecycle = AppLifecycleListener(
        onResume: _onResume,
        onPause: _onBackground,
        onHide: _onBackground,
      );
    } catch (error) {
      _error = friendlyError(error);
    } finally {
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> _onAuthStateChanged(AuthState state) async {
    if (!_cloudConfigured) {
      return;
    }
    if (state.event == AuthChangeEvent.passwordRecovery) {
      _passwordRecovery = true;
    }

    final bool wasSignedIn = _isSignedIn;
    _isSignedIn = _authService.isSignedIn;
    _isVerified = _authService.isEmailVerified;

    if (_isSignedIn) {
      await _ensureSessionStarted();
    } else if (wasSignedIn) {
      await _endSession();
    }
    notifyListeners();
  }

  /// Runs once per signed-in user: realtime, first sync, default folder.
  Future<void> _ensureSessionStarted() async {
    final String userId = _authService.currentUserId;
    if (_sessionStartedFor == userId) {
      return;
    }
    _sessionStartedFor = userId;
    _syncState = SyncState.idle;

    await _refreshData();
    _syncService.startRealtime(_onRemoteChange);
    await syncNow(quiet: true);
    // Create the default folder only after the first pull, so a new device
    // adopts the account's existing Inbox instead of making a duplicate.
    await _ensureInbox();
    await _mergeDuplicateInboxes();
  }

  Future<void> _endSession() async {
    _sessionStartedFor = null;
    await _syncService.stopRealtime();
    _notes = <NoteItem>[];
    _folders = <FolderItem>[];
    _selectedNoteIds.clear();
    _selectionMode = false;
    _view = NotebookView.all;
    _selectedFolderId = null;
    _selectedTag = null;
    _unlockedFolderIds.clear();
    _lastSyncedAt = null;
    _pendingCount = 0;
  }

  void _onResume() {
    unawaited(syncNow(quiet: true));
    _checkDueReminders();
  }

  void _onBackground() {
    // Upload anything waiting before the OS may suspend us, and re-lock
    // private folders so they need authentication again.
    if (_syncService.pendingCount > 0) {
      unawaited(syncNow(pull: false, quiet: true));
    }
    if (_unlockedFolderIds.isNotEmpty) {
      _unlockedFolderIds.clear();
      if (_view == NotebookView.folder &&
          isFolderLocked(_selectedFolderId ?? '')) {
        _view = NotebookView.all;
        _selectedFolderId = null;
      }
      notifyListeners();
    }
  }

  // ===========================================================================
  // Auth
  // ===========================================================================

  void clearMessages() {
    if (_error == null && _notice == null) {
      return;
    }
    _error = null;
    _notice = null;
    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _runBusy(() async {
      _notice = null;
      await _authService.signInWithEmail(email: email, password: password);
      _isSignedIn = _authService.isSignedIn;
      _isVerified = _authService.isEmailVerified;
    });
    if (_isSignedIn) {
      await _ensureSessionStarted();
    }
  }

  Future<void> createAccountWithEmail({
    required String email,
    required String password,
  }) async {
    bool signedIn = false;
    await _runBusy(() async {
      _notice = null;
      signedIn = await _authService.createAccountWithEmail(
        email: email,
        password: password,
      );
      _isSignedIn = _authService.isSignedIn;
      _isVerified = _authService.isEmailVerified;
      if (!signedIn) {
        _notice = 'Account created. Check your inbox to confirm your email, '
            'then sign in.';
      }
    });
    if (signedIn) {
      await _ensureSessionStarted();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _runBusy(() async {
      _notice = null;
      await _authService.sendPasswordReset(email);
      _notice = 'If an account exists for ${email.trim()}, a reset link is on '
          'its way. Open it on any device to choose a new password.';
    });
  }

  /// Finishes the reset flow started from an emailed link.
  Future<bool> completePasswordRecovery(String newPassword) async {
    bool ok = false;
    await _runBusy(() async {
      await _authService.updatePassword(newPassword);
      _passwordRecovery = false;
      ok = true;
    });
    return ok;
  }

  void dismissPasswordRecovery() {
    _passwordRecovery = false;
    notifyListeners();
  }

  Future<void> resendVerificationEmail() async {
    await _runBusy(() async {
      await _authService.sendVerificationEmail();
      _notice = 'Verification email sent.';
    });
  }

  Future<void> refreshVerificationStatus() async {
    await _runBusy(() async {
      await _authService.reloadUser();
      _isVerified = _authService.isEmailVerified;
    });
  }

  Future<void> signOut() async {
    await _runBusy(() async {
      if (_syncService.pendingCount > 0) {
        await syncNow(pull: false, quiet: true);
      }
      if (_cloudConfigured) {
        await _authService.signOut();
      }
      await _localStore.saveOfflineAccessGranted(false);
      _isSignedIn = false;
      _isVerified = false;
      await _endSession();
      _syncState = _cloudConfigured ? SyncState.idle : SyncState.localOnly;
    });
  }

  Future<void> continueInLocalMode() async {
    await _runBusy(() async {
      _error = null;
      await _localStore.saveOfflineAccessGranted(true);
      _isSignedIn = true;
      _isVerified = true;
      await _refreshData();
      await _ensureInbox();
    });
  }

  Future<void> retryCloudSetup() async {
    await _runBusy(() async {
      _error = null;
      await _authService.initialize();
      _cloudConfigured = _authService.isCloudReady;
      if (_cloudConfigured) {
        await _localStore.saveOfflineAccessGranted(false);
        _isSignedIn = _authService.isSignedIn;
        _isVerified = _authService.isEmailVerified;
      }
    });
  }

  Future<void> deleteAccountAndData() async {
    await _runBusy(() async {
      final String ownerId = _activeUserId;
      if (_cloudConfigured) {
        await _storageService.deleteImagesByUrl(
          _notes.expand((NoteItem n) => _imagesOf(n)),
        );
      }
      await _localStore.clearUserData(ownerId);
      if (_cloudConfigured) {
        try {
          await _authService.deleteCurrentAccount();
        } catch (_) {
          await _authService.signOut();
        }
      }
      await _localStore.saveOfflineAccessGranted(false);
      _isSignedIn = false;
      _isVerified = false;
      await _endSession();
    });
  }

  Future<void> setStaySignedIn(bool value) async {
    _staySignedIn = value;
    await _localStore.saveStaySignedIn(value);
    notifyListeners();
  }

  // ===========================================================================
  // Navigation, search, sort, layout
  // ===========================================================================

  void openView(NotebookView view) {
    _view = view;
    _selectedFolderId = null;
    _selectedTag = null;
    _selectedNoteIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  /// Opens a folder, asking for device authentication first if it is locked.
  /// Returns false if the user could not be verified.
  Future<bool> openFolder(String folderId) async {
    if (isFolderLocked(folderId) && !_unlockedFolderIds.contains(folderId)) {
      final bool ok = await _privacyLockService.authenticate(
        reason: 'Unlock "${folderById(folderId)?.name ?? 'folder'}"',
      );
      if (!ok) {
        return false;
      }
      _unlockedFolderIds.add(folderId);
    }
    _view = NotebookView.folder;
    _selectedFolderId = folderId;
    _selectedTag = null;
    _selectedNoteIds.clear();
    _selectionMode = false;
    notifyListeners();
    return true;
  }

  void openTag(String tag) {
    _view = NotebookView.tag;
    _selectedTag = tag;
    _selectedFolderId = null;
    _selectedNoteIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  Future<void> setSort(NoteSort sort) async {
    _sort = sort;
    await _localStore.saveSetting('note_sort', sort.name);
    notifyListeners();
  }

  Future<void> setLayout(NoteLayout layout) async {
    _layout = layout;
    await _localStore.saveSetting('note_layout', layout.name);
    notifyListeners();
  }

  // ===========================================================================
  // Folders
  // ===========================================================================

  Future<FolderItem> createFolder({required String name, String? parentId}) async {
    final DateTime now = DateTime.now().toUtc();
    final FolderItem folder = FolderItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      name: name.trim(),
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
    await _upsertFolder(folder);
    return folder;
  }

  Future<void> renameFolder(String folderId, String name) async {
    final FolderItem? folder = folderById(folderId);
    final String trimmed = name.trim();
    if (folder == null || trimmed.isEmpty || trimmed == folder.name) {
      return;
    }
    await _upsertFolder(
      folder.copyWith(name: trimmed, updatedAt: DateTime.now().toUtc()),
    );
  }

  /// Moves the folder's notes to the trash, re-parents its sub-folders, then
  /// removes it. Trashed notes are restored into the Inbox later.
  Future<void> deleteFolder(String folderId) async {
    final FolderItem? folder = folderById(folderId);
    if (folder == null) {
      return;
    }
    final DateTime now = DateTime.now().toUtc();
    for (final NoteItem note
        in _notes.where((NoteItem n) => n.folderId == folderId && !n.isDeleted)) {
      await _writeNote(
        note.copyWith(
          isDeleted: true,
          deletedAt: now,
          isPinned: false,
          updatedAt: now,
          localOnly: true,
        ),
      );
    }
    for (final FolderItem child
        in _folders.where((FolderItem f) => f.parentId == folderId)) {
      final FolderItem moved = child.copyWith(
        parentId: folder.parentId,
        clearParent: folder.parentId == null,
        updatedAt: now,
      );
      await _localStore.upsertFolder(moved);
      await _syncService.queueFolderUpsert(moved);
    }
    await _localStore.deleteFolder(folderId);
    await _syncService.queueFolderDelete(folderId);
    _lockedFolderIds.remove(folderId);
    await _localStore.saveLockedFolderIds(_lockedFolderIds);
    _schedulePush();
    await _refreshData();
  }

  /// Locking needs no proof; removing a lock does.
  Future<bool> toggleFolderLock(String folderId) async {
    if (!_lockSupported) {
      return false;
    }
    if (_lockedFolderIds.contains(folderId)) {
      final bool ok = await _privacyLockService.authenticate(
        reason: 'Remove the lock from this folder',
      );
      if (!ok) {
        return false;
      }
      _lockedFolderIds.remove(folderId);
    } else {
      _lockedFolderIds.add(folderId);
      _unlockedFolderIds.remove(folderId);
    }
    await _localStore.saveLockedFolderIds(_lockedFolderIds);
    notifyListeners();
    return true;
  }

  Future<void> _upsertFolder(FolderItem folder) async {
    await _localStore.upsertFolder(folder);
    await _syncService.queueFolderUpsert(folder);
    _schedulePush();
    await _refreshData();
  }

  String _inboxIdFor(String ownerId) =>
      _uuid.v5(Namespace.url.value, 'https://universal-notebook.app/inbox/$ownerId');

  String get _defaultFolderId {
    final String deterministic = _inboxIdFor(_activeUserId);
    if (_folders.any((FolderItem f) => f.id == deterministic)) {
      return deterministic;
    }
    for (final FolderItem folder in _folders) {
      if (folder.parentId == null && folder.name.toLowerCase() == 'inbox') {
        return folder.id;
      }
    }
    return _folders.isNotEmpty ? _folders.first.id : deterministic;
  }

  /// Every account has at least one folder. The Inbox id is derived from the
  /// user id, so two devices creating it offline produce the same row.
  Future<void> _ensureInbox() async {
    if (!_isSignedIn || _localStore.readFoldersForUser(_activeUserId).isNotEmpty) {
      return;
    }
    final DateTime now = DateTime.now().toUtc();
    await _upsertFolder(
      FolderItem(
        id: _inboxIdFor(_activeUserId),
        ownerId: _activeUserId,
        name: 'Inbox',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Older versions created a separate "Inbox" on every device. Fold those
  /// into one (the oldest), moving their notes across.
  Future<void> _mergeDuplicateInboxes() async {
    final List<FolderItem> inboxes = _folders
        .where((FolderItem f) =>
            f.parentId == null && f.name.trim().toLowerCase() == 'inbox')
        .toList();
    if (inboxes.length < 2) {
      return;
    }
    inboxes.sort((FolderItem a, FolderItem b) {
      final int byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    final FolderItem keep = inboxes.first;
    final DateTime now = DateTime.now().toUtc();

    for (final FolderItem duplicate in inboxes.skip(1)) {
      for (final NoteItem note
          in _notes.where((NoteItem n) => n.folderId == duplicate.id)) {
        await _writeNote(
          note.copyWith(folderId: keep.id, updatedAt: now, localOnly: true),
        );
      }
      await _localStore.deleteFolder(duplicate.id);
      await _syncService.queueFolderDelete(duplicate.id);
      _lockedFolderIds.remove(duplicate.id);
    }
    _schedulePush();
    await _refreshData();
  }

  // ===========================================================================
  // Notes
  // ===========================================================================

  Future<NoteItem> createNote({
    String? folderId,
    String title = '',
    String body = '',
  }) async {
    await _ensureInbox();
    final String target = folderId ??
        (_view == NotebookView.folder ? _selectedFolderId : null) ??
        _defaultFolderId;
    final DateTime now = DateTime.now().toUtc();
    final NoteItem note = NoteItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      folderId: target,
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
      imagePaths: const <String>[],
      tags: _view == NotebookView.tag && _selectedTag != null
          ? <String>[_selectedTag!]
          : const <String>[],
      localOnly: true,
      revision: 0,
      isPinned: _view == NotebookView.pinned,
    );
    await _writeNote(note);
    return note;
  }

  Future<NoteItem> createNoteFromTemplate(TemplateItem template) =>
      createNote(title: template.title, body: template.body);

  /// Persists an edit (stamps the time and marks it for upload).
  Future<void> saveNote(NoteItem note) => _writeNote(
        note.copyWith(updatedAt: DateTime.now().toUtc(), localOnly: true),
      );

  Future<void> togglePin(NoteItem note) =>
      saveNote(note.copyWith(isPinned: !note.isPinned));

  Future<void> archiveNote(NoteItem note) =>
      saveNote(note.copyWith(isArchived: true, isPinned: false));

  Future<void> unarchiveNote(NoteItem note) =>
      saveNote(note.copyWith(isArchived: false));

  Future<void> setNoteColor(NoteItem note, String? colorId) => saveNote(
        colorId == null
            ? note.copyWith(clearColor: true)
            : note.copyWith(colorId: colorId),
      );

  Future<void> moveNoteToFolder(NoteItem note, String folderId) =>
      saveNote(note.copyWith(folderId: folderId));

  Future<void> setTags(NoteItem note, List<String> tags) {
    final List<String> clean = <String>[];
    for (final String raw in tags) {
      final String tag = normalizeTag(raw);
      if (tag.isNotEmpty && !clean.contains(tag)) {
        clean.add(tag);
      }
    }
    return saveNote(note.copyWith(tags: clean));
  }

  static String normalizeTag(String raw) => raw
      .trim()
      .replaceFirst(RegExp(r'^#+'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .toLowerCase();

  Future<void> moveToTrash(NoteItem note) async {
    await saveNote(
      note.copyWith(
        isDeleted: true,
        deletedAt: DateTime.now().toUtc(),
        isArchived: false,
        isPinned: false,
      ),
    );
    await _reminderService.cancelReminder(note.id);
  }

  /// Restores into the note's folder, or the Inbox if that folder is gone.
  Future<void> restoreFromTrash(NoteItem note) async {
    await _ensureInbox();
    final bool folderExists = _folders.any((FolderItem f) => f.id == note.folderId);
    await saveNote(
      note.copyWith(
        isDeleted: false,
        clearDeletedAt: true,
        folderId: folderExists ? note.folderId : _defaultFolderId,
      ),
    );
    if (note.reminderAt != null && note.reminderAt!.isAfter(DateTime.now())) {
      await _scheduleNative(note);
    }
  }

  Future<void> permanentlyDeleteNote(String noteId) async {
    await _deleteForever(<String>[noteId]);
  }

  Future<void> emptyTrash() async {
    await _deleteForever(trashNotes.map((NoteItem n) => n.id).toList());
  }

  /// Deletes a note that was created and left empty (no title, text or
  /// images), so abandoned "New note" taps don't litter the notebook.
  Future<void> discardIfEmpty(String noteId) async {
    final NoteItem? note = getNoteById(noteId);
    if (note != null && note.isEmpty && note.imagePaths.isEmpty) {
      await _deleteForever(<String>[noteId]);
    }
  }

  Future<void> _deleteForever(List<String> noteIds) async {
    if (noteIds.isEmpty) {
      return;
    }
    final List<String> images = <String>[];
    for (final String id in noteIds) {
      final NoteItem? note = getNoteById(id);
      if (note != null) {
        images.addAll(_imagesOf(note));
      }
      await _localStore.deleteNote(id);
      await _localStore.clearNoteVersions(id);
      await _reminderService.cancelReminder(id);
      if (_cloudConfigured) {
        // Harmless if the row never reached the cloud; required if it did or
        // if an upload is in flight.
        await _syncService.queueNoteDelete(id);
      }
    }
    if (_cloudConfigured && images.isNotEmpty) {
      unawaited(_storageService.deleteImagesByUrl(images));
    }
    _selectedNoteIds.removeAll(noteIds);
    _selectionMode = _selectedNoteIds.isNotEmpty;
    _schedulePush();
    await _refreshData();
  }

  Future<void> _purgeExpiredTrash() async {
    final DateTime cutoff = DateTime.now().toUtc().subtract(_trashRetention);
    final List<String> expired = _notes
        .where((NoteItem n) =>
            n.isDeleted && (n.deletedAt ?? n.updatedAt).isBefore(cutoff))
        .map((NoteItem n) => n.id)
        .toList();
    await _deleteForever(expired);
  }

  List<NoteItem> getVersionHistory(String noteId) =>
      _localStore.readNoteVersions(noteId);

  Future<void> restoreVersion({
    required String noteId,
    required NoteItem version,
  }) async {
    await saveNote(
      version.copyWith(
        id: noteId,
        isDeleted: false,
        clearDeletedAt: true,
      ),
    );
  }

  Future<void> _writeNote(NoteItem note) async {
    await _localStore.upsertNote(note);
    await _localStore.appendNoteVersion(note);
    await _syncService.queueNoteUpsert(note);
    _schedulePush();
    await _refreshData();
  }

  // ===========================================================================
  // Images
  // ===========================================================================

  Future<String> uploadNoteImage({
    required String noteId,
    required Uint8List bytes,
    required String fileExtension,
  }) {
    return _storageService.uploadNoteImage(
      userId: _activeUserId,
      noteId: noteId,
      bytes: bytes,
      fileExtension: fileExtension,
    );
  }

  Future<void> attachImageToNote({
    required NoteItem note,
    required String imagePath,
  }) {
    return saveNote(
      note.copyWith(imagePaths: <String>[...note.imagePaths, imagePath]),
    );
  }

  /// Removes an image from the note (attachment list and inline Markdown) and
  /// deletes the stored file.
  Future<NoteItem?> removeImageFromNote({
    required NoteItem note,
    required String imagePath,
  }) async {
    final NoteItem updated = note.copyWith(
      body: MarkdownTools.removeImage(note.body, imagePath),
      imagePaths: note.imagePaths
          .where((String path) => path != imagePath)
          .toList(growable: false),
    );
    await saveNote(updated);
    if (_cloudConfigured) {
      unawaited(_storageService.deleteImagesByUrl(<String>[imagePath]));
    }
    return getNoteById(note.id);
  }

  Iterable<String> _imagesOf(NoteItem note) => <String>{
        ...note.imagePaths,
        ...MarkdownTools.imageUrls(note.body),
      };

  // ===========================================================================
  // Reminders
  // ===========================================================================

  /// Returns false if the platform refused notification permission (the
  /// reminder is still saved and shows in the Reminders view).
  Future<bool> setReminder(NoteItem note, DateTime at) async {
    bool allowed = true;
    if (_reminderService.nativeSupported) {
      allowed = await _reminderService.requestPermission();
    }
    final NoteItem updated = note.copyWith(reminderAt: at.toUtc());
    await saveNote(updated);
    await _scheduleNative(updated);
    return allowed;
  }

  Future<void> clearReminder(NoteItem note) async {
    await saveNote(note.copyWith(clearReminder: true));
    await _reminderService.cancelReminder(note.id);
    dismissReminderAlert(note);
  }

  Future<void> _scheduleNative(NoteItem note) async {
    final DateTime? at = note.reminderAt;
    if (at == null || note.isDeleted) {
      await _reminderService.cancelReminder(note.id);
      return;
    }
    await _reminderService.scheduleReminder(
      noteId: note.id,
      title: note.displayTitle.isEmpty ? 'Note reminder' : note.displayTitle,
      body: MarkdownTools.previewText(note.body),
      when: at.toLocal(),
    );
  }

  void _startReminderWatcher() {
    if (_reminderService.nativeSupported) {
      return; // the OS delivers these
    }
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 20),
      (Timer _) => _checkDueReminders(),
    );
    _checkDueReminders();
  }

  String _reminderKey(NoteItem note) =>
      '${note.id}@${note.reminderAt!.millisecondsSinceEpoch}';

  void _checkDueReminders() {
    if (_reminderService.nativeSupported || !_isSignedIn) {
      return;
    }
    final DateTime now = DateTime.now();
    final Set<String> showing =
        reminderAlerts.value.map((NoteItem n) => n.id).toSet();
    final List<NoteItem> due = _notes.where((NoteItem note) {
      final DateTime? at = note.reminderAt;
      return at != null &&
          !note.isDeleted &&
          !at.isAfter(now) &&
          now.difference(at) < const Duration(hours: 24) &&
          !showing.contains(note.id) &&
          !_firedReminderKeys.contains(_reminderKey(note));
    }).toList();
    if (due.isNotEmpty) {
      reminderAlerts.value = <NoteItem>[...reminderAlerts.value, ...due];
    }
  }

  void dismissReminderAlert(NoteItem note) {
    if (note.reminderAt != null) {
      _firedReminderKeys.add(_reminderKey(note));
      unawaited(_localStore.saveStringSet('fired_reminders', _firedReminderKeys));
    }
    reminderAlerts.value = reminderAlerts.value
        .where((NoteItem n) => n.id != note.id)
        .toList(growable: false);
  }

  // ===========================================================================
  // Dictation and AI
  // ===========================================================================

  /// Starts dictation. The microphone permission is requested on first use
  /// rather than at app launch.
  Future<void> startSpeechCapture({
    required void Function(SpeechCaptureResult result) onResult,
  }) async {
    if (!_speechReady) {
      _speechReady = await _speechService.initialize();
      if (!_speechReady) {
        throw StateError(
          'Dictation is unavailable. Check that microphone access is allowed.',
        );
      }
    }
    await _speechService.startListening(onResult: onResult);
  }

  Future<void> stopSpeechCapture() => _speechService.stopListening();

  Future<String> summarizeText(String text) => _aiService.summarize(text);

  Future<String> cleanUpText(String text) => _aiService.cleanUp(text);

  Future<void> suggestAndAddTags(NoteItem note) async {
    final List<String> suggested = await _aiService.suggestTags(note.body);
    if (suggested.isNotEmpty) {
      await setTags(note, <String>[...note.tags, ...suggested]);
    }
  }

  // ===========================================================================
  // Sharing, export, templates
  // ===========================================================================

  Future<void> shareNote(NoteItem note) => _shareService.shareNoteWithImages(
        title: note.displayTitle,
        body: note.body,
        imagePaths: note.imagePaths,
      );

  Future<void> exportNoteAsTxt(NoteItem note) =>
      _shareService.exportNoteAsTxt(note);

  Future<void> exportNoteAsPdf(NoteItem note) =>
      _shareService.exportNoteAsPdf(note);

  Future<void> exportAllDataBackup() => _shareService.exportBackupJson(
        notes: _notes,
        folders: _folders,
        templates: _templates,
      );

  Future<void> saveCustomTemplate({
    required String title,
    required String body,
  }) async {
    await _templateService.saveCustomTemplate(
      TemplateItem(
        id: _uuid.v4(),
        title: title.trim(),
        body: body,
        ownerId: _activeUserId,
      ),
    );
    await _refreshData();
  }

  Future<void> deleteCustomTemplate(String templateId) async {
    await _templateService.deleteCustomTemplate(templateId);
    await _refreshData();
  }

  // ===========================================================================
  // Selection and bulk actions
  // ===========================================================================

  void enterSelectionMode(String noteId) {
    _selectionMode = true;
    _selectedNoteIds.add(noteId);
    notifyListeners();
  }

  /// Selection mode with nothing picked yet (the desktop "Select" button,
  /// since long-press is not a natural mouse gesture).
  void startSelection() {
    _selectionMode = true;
    notifyListeners();
  }

  void toggleNoteSelection(String noteId) {
    if (!_selectedNoteIds.remove(noteId)) {
      _selectedNoteIds.add(noteId);
    }
    _selectionMode = _selectedNoteIds.isNotEmpty;
    notifyListeners();
  }

  void selectAllVisible() {
    _selectedNoteIds.addAll(visibleNotes.map((NoteItem n) => n.id));
    _selectionMode = _selectedNoteIds.isNotEmpty;
    notifyListeners();
  }

  void clearSelection() {
    if (!_selectionMode && _selectedNoteIds.isEmpty) {
      return;
    }
    _selectedNoteIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  Future<void> _forSelected(Future<void> Function(NoteItem note) action) async {
    final List<NoteItem> targets = selectedNotes;
    clearSelection();
    for (final NoteItem note in targets) {
      await action(note);
    }
  }

  Future<void> moveSelectedToTrash() => _forSelected(moveToTrash);

  Future<void> archiveSelected() => _forSelected((NoteItem note) async {
        if (!note.isArchived) {
          await archiveNote(note);
        }
      });

  Future<void> unarchiveSelected() => _forSelected(unarchiveNote);

  Future<void> restoreSelected() => _forSelected(restoreFromTrash);

  Future<void> deleteSelectedForever() async {
    final List<String> ids = _selectedNoteIds.toList();
    clearSelection();
    await _deleteForever(ids);
  }

  Future<void> moveSelectedToFolder(String folderId) =>
      _forSelected((NoteItem note) async {
        if (note.folderId != folderId) {
          await moveNoteToFolder(note, folderId);
        }
      });

  Future<void> colorSelected(String? colorId) =>
      _forSelected((NoteItem note) => setNoteColor(note, colorId));

  /// Pins all selected notes, or unpins them if they are all pinned already.
  Future<void> togglePinSelected() async {
    final bool allPinned = selectedNotes.every((NoteItem n) => n.isPinned);
    await _forSelected(
      (NoteItem note) => saveNote(note.copyWith(isPinned: !allPinned)),
    );
  }

  Future<void> shareSelected() async {
    final List<NoteItem> targets = selectedNotes;
    if (targets.isEmpty) {
      return;
    }
    await _shareService.shareNotes(targets);
    clearSelection();
  }

  // ===========================================================================
  // Sync orchestration
  // ===========================================================================

  /// Pushes local edits and (optionally) pulls remote ones. [quiet] keeps the
  /// status indicator still for routine background checks with nothing to
  /// upload. Returns true if everything completed.
  Future<bool> syncNow({bool pull = true, bool quiet = false}) async {
    if (!_cloudConfigured || !_isSignedIn) {
      return false;
    }
    if (_syncRunning) {
      _syncAgain = true;
      _syncAgainPull = _syncAgainPull || pull;
      return true;
    }
    _syncRunning = true;
    _pendingCount = _syncService.pendingCount;
    if (!quiet || _pendingCount > 0) {
      _syncState = SyncState.syncing;
      notifyListeners();
    }

    bool ok = false;
    try {
      if (!await _syncService.hasConnection()) {
        _syncState = SyncState.offline;
        return false;
      }
      ok = await _syncService.pushPending();
      if (pull) {
        final PullOutcome? outcome = await _syncService.pull();
        if (outcome == null) {
          ok = false;
        } else {
          _lastPullAt = DateTime.now();
          if (outcome.hasChanges) {
            await _afterPull(outcome);
          }
        }
      }
      _syncState = ok ? SyncState.idle : SyncState.error;
      if (ok) {
        _lastSyncedAt = DateTime.now();
      }
      return ok;
    } catch (_) {
      _syncState = SyncState.error;
      return false;
    } finally {
      _syncRunning = false;
      await _refreshData();
      if (_syncAgain) {
        final bool again = _syncAgainPull;
        _syncAgain = false;
        _syncAgainPull = false;
        unawaited(syncNow(pull: again, quiet: true));
      }
    }
  }

  Future<void> _afterPull(PullOutcome outcome) async {
    await _refreshData();
    await _mergeDuplicateInboxes();
    await _ensureInbox();
    // Reminders set on another device should ring on this one too.
    for (final NoteItem note in outcome.changedNotes) {
      await _scheduleNative(note);
    }
    for (final String id in outcome.deletedNoteIds) {
      await _reminderService.cancelReminder(id);
    }
    _checkDueReminders();
  }

  void _periodicSync() {
    if (!_cloudConfigured || !_isSignedIn) {
      return;
    }
    final bool pullDue = !_syncService.realtimeConnected ||
        _lastPullAt == null ||
        DateTime.now().difference(_lastPullAt!) > const Duration(minutes: 2);
    if (_syncService.pendingCount == 0 && !pullDue) {
      return;
    }
    unawaited(syncNow(pull: pullDue, quiet: true));
  }

  /// Uploads shortly after an edit (debounced so typing sends one request).
  void _schedulePush() {
    _pendingCount = _syncService.pendingCount;
    if (!_cloudConfigured || !_isSignedIn) {
      return;
    }
    _pushDebounce?.cancel();
    _pushDebounce = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(syncNow(pull: false, quiet: true)),
    );
  }

  void _onRemoteChange() {
    _pullDebounce?.cancel();
    _pullDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(syncNow(quiet: true)),
    );
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  Future<void> _refreshData() async {
    final String ownerId = _activeUserId;
    _folders = _localStore.readFoldersForUser(ownerId);
    _notes = _localStore.readNotesForUser(ownerId);
    _templates = await _templateService.getTemplatesForUser(ownerId);
    _pendingCount = _syncService.pendingCount;

    if (_view == NotebookView.folder &&
        !_folders.any((FolderItem f) => f.id == _selectedFolderId)) {
      _view = NotebookView.all;
      _selectedFolderId = null;
    }
    if (_selectedNoteIds.isNotEmpty) {
      final Set<String> ids = _notes.map((NoteItem n) => n.id).toSet();
      _selectedNoteIds.removeWhere((String id) => !ids.contains(id));
      _selectionMode = _selectedNoteIds.isNotEmpty;
    }
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await task();
    } catch (error) {
      _error = friendlyError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String get _activeUserId =>
      _cloudConfigured ? _authService.currentUserId : 'local-offline-user';

  @override
  void dispose() {
    _authSubscription?.cancel();
    _lifecycle?.dispose();
    _syncTimer?.cancel();
    _pushDebounce?.cancel();
    _pullDebounce?.cancel();
    _reminderTimer?.cancel();
    unawaited(_syncService.stopRealtime());
    unawaited(_authService.dispose());
    _aiService.dispose();
    reminderAlerts.dispose();
    super.dispose();
  }
}
