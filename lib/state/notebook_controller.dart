import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/models/folder_item.dart';
import '../core/models/note_item.dart';
import '../core/models/template_item.dart';
import '../core/theme/theme_controller.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/local_store_service.dart';
import '../services/ocr_service.dart';
import '../services/privacy_lock_service.dart';
import '../services/reminder_service.dart';
import '../services/share_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/template_service.dart';

class NotebookController extends ChangeNotifier {
  NotebookController({
    required AuthService authService,
    required LocalStoreService localStoreService,
    required SyncService syncService,
    required TemplateService templateService,
    required ThemeController themeController,
    required SpeechService speechService,
    required OcrService ocrService,
    required ReminderService reminderService,
    required ShareService shareService,
    required PrivacyLockService privacyLockService,
    required AiService aiService,
    required StorageService storageService,
  })  : _authService = authService,
        _localStoreService = localStoreService,
        _syncService = syncService,
        _templateService = templateService,
        _themeController = themeController,
        _speechService = speechService,
        _ocrService = ocrService,
        _reminderService = reminderService,
        _shareService = shareService,
        _privacyLockService = privacyLockService,
        _aiService = aiService,
        _storageService = storageService;

  final AuthService _authService;
  final LocalStoreService _localStoreService;
  final SyncService _syncService;
  final TemplateService _templateService;
  final ThemeController _themeController;
  final SpeechService _speechService;
  final OcrService _ocrService;
  final ReminderService _reminderService;
  final ShareService _shareService;
  final PrivacyLockService _privacyLockService;
  final AiService _aiService;
  final StorageService _storageService;

  final Uuid _uuid = const Uuid();

  StreamSubscription<dynamic>? _authSubscription;
  Timer? _syncTimer;

  bool _isBootstrapping = true;
  bool _isBusy = false;
  bool _isSignedIn = false;
  bool _isVerified = false;
  bool _cloudConfigured = false;
  bool _staySignedIn = true;
  bool _speechAvailable = false;
  String? _error;

  String _searchQuery = '';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  bool _hasImageFilter = false;
  bool _showArchived = false;
  String? _selectedFolderId;

  bool _selectionMode = false;
  final Set<String> _selectedNoteIds = <String>{};

  List<NoteItem> _notes = <NoteItem>[];
  List<FolderItem> _folders = <FolderItem>[];
  List<TemplateItem> _templates = <TemplateItem>[];
  List<TemplateItem> _marketplaceTemplates = <TemplateItem>[];
  Set<String> _lockedFolderIds = <String>{};

  bool get isBootstrapping => _isBootstrapping;
  bool get isBusy => _isBusy;
  bool get isSignedIn => _isSignedIn;
  bool get isVerified => _isVerified;
  bool get cloudConfigured => _cloudConfigured;
  bool get staySignedIn => _staySignedIn;
  bool get speechAvailable => _speechAvailable;
  String? get cloudStatusMessage => _authService.initializationError;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  bool get hasImageFilter => _hasImageFilter;
  bool get showArchived => _showArchived;
  String? get selectedFolderId => _selectedFolderId;

  bool get selectionMode => _selectionMode;
  Set<String> get selectedNoteIds => _selectedNoteIds;
  int get selectedCount => _selectedNoteIds.length;
  bool isNoteSelected(String noteId) => _selectedNoteIds.contains(noteId);
  List<NoteItem> get selectedNotes => _notes
      .where((NoteItem note) => _selectedNoteIds.contains(note.id))
      .toList(growable: false);

  List<NoteItem> get notes => _notes;
  List<FolderItem> get folders => _folders;
  List<TemplateItem> get templates => _templates;
  List<TemplateItem> get marketplaceTemplates => _marketplaceTemplates;
  Set<String> get lockedFolderIds => _lockedFolderIds;

  List<NoteItem> get archivedNotes => _notes
      .where((NoteItem note) => note.isArchived && !note.isDeleted)
      .toList(growable: false)
    ..sort((NoteItem a, NoteItem b) => b.updatedAt.compareTo(a.updatedAt));

  List<NoteItem> get trashNotes =>
      _notes.where((NoteItem note) => note.isDeleted).toList(growable: false)
        ..sort((NoteItem a, NoteItem b) => b.updatedAt.compareTo(a.updatedAt));

  NoteItem? getNoteById(String noteId) {
    for (final NoteItem note in _notes) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  bool get hasNotebookAccess =>
      _isSignedIn && (!_cloudConfigured || _isVerified);

  List<NoteItem> get filteredNotes {
    final String query = _searchQuery.trim().toLowerCase();

    final List<NoteItem> filtered = _notes.where((NoteItem note) {
      if (note.isDeleted) {
        return false;
      }

      if (!_showArchived && note.isArchived) {
        return false;
      }

      if (_selectedFolderId != null && note.folderId != _selectedFolderId) {
        return false;
      }

      if (_hasImageFilter && note.imagePaths.isEmpty) {
        return false;
      }

      if (_filterStartDate != null &&
          note.updatedAt.toLocal().isBefore(_filterStartDate!)) {
        return false;
      }

      if (_filterEndDate != null &&
          note.updatedAt.toLocal().isAfter(
                _filterEndDate!.add(const Duration(days: 1)),
              )) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      return note.title.toLowerCase().contains(query) ||
          note.body.toLowerCase().contains(query) ||
          note.tags.any((String tag) => tag.toLowerCase().contains(query));
    }).toList(growable: false);

    filtered.sort((NoteItem a, NoteItem b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return filtered;
  }

  Future<void> initialize() async {
    _isBootstrapping = true;
    _error = null;
    notifyListeners();

    try {
      await _localStoreService.init();
      await _authService.initialize();
      await _reminderService.initialize();
      await _themeController.initialize();

      _speechAvailable = await _speechService.initialize();
      _staySignedIn = _localStoreService.readStaySignedIn();
      _lockedFolderIds = _localStoreService.readLockedFolderIds();

      _cloudConfigured = _authService.isCloudReady;
      if (_cloudConfigured) {
        _isSignedIn = _authService.isSignedIn;
        _isVerified = _authService.isEmailVerified;
      } else {
        final bool offlineAccessGranted =
            _localStoreService.readOfflineAccessGranted();
        _isSignedIn = offlineAccessGranted;
        _isVerified = offlineAccessGranted;
      }

      _authSubscription =
          _authService.authStateChanges().listen((dynamic _) async {
        if (!_cloudConfigured) {
          return;
        }
        _isSignedIn = _authService.isSignedIn;
        _isVerified = _authService.isEmailVerified;
        await _refreshData();
      });

      await _refreshData();
      _marketplaceTemplates =
          await _templateService.fetchMarketplaceTemplates();
      _syncTimer = Timer.periodic(
        const Duration(seconds: 20),
        (Timer _) => syncNow(),
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> createAccountWithEmail({
    required String email,
    required String password,
  }) async {
    await _runBusy(() async {
      if (!_cloudConfigured) {
        throw StateError(
          'Cloud sign-in is unavailable. Configure cloud sync first.',
        );
      }

      _error = null;
      await _authService.createAccountWithEmail(
          email: email, password: password);
      _isSignedIn = true;
      _isVerified = _authService.isEmailVerified;
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _runBusy(() async {
      if (!_cloudConfigured) {
        throw StateError(
          'Cloud sign-in is unavailable. Configure cloud sync first.',
        );
      }

      _error = null;
      await _authService.signInWithEmail(email: email, password: password);
      _isSignedIn = true;
      _isVerified = _authService.isEmailVerified;
      await _refreshData();
    });
  }

  Future<void> resendVerificationEmail() async {
    await _runBusy(() => _authService.sendVerificationEmail());
  }

  Future<void> refreshVerificationStatus() async {
    await _runBusy(() async {
      await _authService.reloadUser();
      _isVerified = _authService.isEmailVerified;
    });
  }

  Future<void> signOut() async {
    await _runBusy(() async {
      if (_cloudConfigured) {
        await _authService.signOut();
      }

      await _localStoreService.saveOfflineAccessGranted(false);
      _isSignedIn = false;
      _isVerified = false;
      _notes = <NoteItem>[];
      _folders = <FolderItem>[];
      _templates = <TemplateItem>[];
      _selectedFolderId = null;
      _selectedNoteIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> continueInLocalMode() async {
    await _runBusy(() async {
      _error = null;
      await _localStoreService.saveOfflineAccessGranted(true);
      _isSignedIn = true;
      _isVerified = true;
      await _refreshData();
    });
  }

  Future<void> retryCloudSetup() async {
    await _runBusy(() async {
      _error = null;
      await _authService.initialize();

      _cloudConfigured = _authService.isCloudReady;
      if (_cloudConfigured) {
        await _localStoreService.saveOfflineAccessGranted(false);
        _isSignedIn = _authService.isSignedIn;
        _isVerified = _authService.isEmailVerified;
      } else {
        final bool offlineAccessGranted =
            _localStoreService.readOfflineAccessGranted();
        _isSignedIn = offlineAccessGranted;
        _isVerified = offlineAccessGranted;
      }
    });
  }

  Future<void> deleteAccountAndData() async {
    await _runBusy(() async {
      final String ownerId = _activeUserId;
      await _localStoreService.clearUserData(ownerId);

      if (_cloudConfigured) {
        try {
          await _authService.deleteCurrentAccount();
        } catch (_) {
          await _authService.signOut();
        }
      }

      await _localStoreService.saveOfflineAccessGranted(false);
      _isSignedIn = false;
      _isVerified = false;
      _notes = <NoteItem>[];
      _folders = <FolderItem>[];
      _templates = <TemplateItem>[];
      _selectedFolderId = null;
      _selectedNoteIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> setStaySignedIn(bool value) async {
    _staySignedIn = value;
    await _localStoreService.saveStaySignedIn(value);
    notifyListeners();
  }

  Future<FolderItem> createFolder({
    required String name,
    String? parentId,
  }) async {
    final FolderItem folder = FolderItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      name: name.trim(),
      parentId: parentId,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    await _localStoreService.upsertFolder(folder);
    await _syncService.queueFolderUpsert(folder);
    await _refreshData();
    return folder;
  }

  Future<void> deleteFolder(String folderId) async {
    final List<NoteItem> notesInFolder =
        _notes.where((NoteItem note) => note.folderId == folderId).toList();

    for (final NoteItem note in notesInFolder) {
      await deleteNote(note.id);
    }

    await _localStoreService.deleteFolder(folderId);
    await _syncService.queueFolderDelete(folderId);

    _lockedFolderIds.remove(folderId);
    await _localStoreService.saveLockedFolderIds(_lockedFolderIds);

    await _refreshData();
  }

  Future<void> toggleFolderLock(String folderId) async {
    if (_lockedFolderIds.contains(folderId)) {
      _lockedFolderIds.remove(folderId);
    } else {
      _lockedFolderIds.add(folderId);
    }

    await _localStoreService.saveLockedFolderIds(_lockedFolderIds);
    notifyListeners();
  }

  bool isFolderLocked(String folderId) => _lockedFolderIds.contains(folderId);

  Future<bool> unlockFolder(String folderId) async {
    if (!isFolderLocked(folderId)) {
      return true;
    }

    final bool unlocked = await _privacyLockService.authenticate(
      reason: 'Unlock this notebook folder',
    );
    return unlocked;
  }

  Future<NoteItem> createBlankNote({String? folderId}) async {
    final String targetFolderId = folderId ?? _defaultFolderId;
    final NoteItem note = NoteItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      folderId: targetFolderId,
      title: 'Untitled note',
      body: '',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      reminderAt: null,
      imagePaths: const <String>[],
      tags: const <String>[],
      localOnly: true,
      revision: 0,
      conflictGroupId: null,
    );

    await _upsertNote(note);
    return note;
  }

  Future<NoteItem> createNoteFromTemplate({
    required TemplateItem template,
    String? folderId,
  }) async {
    final NoteItem note = NoteItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      folderId: folderId ?? _defaultFolderId,
      title: template.title,
      body: template.body,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      reminderAt: null,
      imagePaths: const <String>[],
      tags: const <String>[],
      localOnly: true,
      revision: 0,
      conflictGroupId: null,
    );

    await _upsertNote(note);
    return note;
  }

  Future<void> saveNote(NoteItem note) {
    return _upsertNote(
      note.copyWith(
        updatedAt: DateTime.now().toUtc(),
        localOnly: true,
      ),
    );
  }

  Future<void> togglePin(NoteItem note) {
    return saveNote(note.copyWith(isPinned: !note.isPinned));
  }

  Future<void> archiveNote(NoteItem note) {
    return saveNote(note.copyWith(isArchived: true, isPinned: false));
  }

  Future<void> unarchiveNote(NoteItem note) {
    return saveNote(note.copyWith(isArchived: false));
  }

  Future<void> moveToTrash(NoteItem note) {
    return saveNote(
      note.copyWith(
        isDeleted: true,
        deletedAt: DateTime.now().toUtc(),
        isArchived: false,
        isPinned: false,
      ),
    );
  }

  Future<void> restoreFromTrash(NoteItem note) {
    return saveNote(
      note.copyWith(
        isDeleted: false,
        clearDeletedAt: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-select and bulk actions
  // ---------------------------------------------------------------------------

  void enterSelectionMode(String noteId) {
    _selectionMode = true;
    _selectedNoteIds.add(noteId);
    notifyListeners();
  }

  void toggleNoteSelection(String noteId) {
    if (!_selectedNoteIds.remove(noteId)) {
      _selectedNoteIds.add(noteId);
    }
    _selectionMode = _selectedNoteIds.isNotEmpty;
    notifyListeners();
  }

  void selectAllNotes(Iterable<String> noteIds) {
    _selectedNoteIds.addAll(noteIds);
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

  Future<void> moveSelectedToTrash() async {
    for (final NoteItem note in selectedNotes) {
      await moveToTrash(note);
    }
    clearSelection();
  }

  Future<void> archiveSelected() async {
    for (final NoteItem note in selectedNotes) {
      if (!note.isArchived) {
        await archiveNote(note);
      }
    }
    clearSelection();
  }

  Future<void> moveSelectedToFolder(String folderId) async {
    for (final NoteItem note in selectedNotes) {
      if (note.folderId != folderId) {
        await saveNote(note.copyWith(folderId: folderId));
      }
    }
    clearSelection();
  }

  Future<void> shareSelected() async {
    final List<NoteItem> targets = selectedNotes;
    if (targets.isEmpty) {
      return;
    }
    await _shareService.shareNotes(targets);
    clearSelection();
  }

  Future<void> attachImageToNote({
    required NoteItem note,
    required String imagePath,
  }) async {
    final List<String> updatedPaths = <String>[...note.imagePaths, imagePath];
    await saveNote(note.copyWith(imagePaths: updatedPaths));
  }

  /// Inline images are stored in Supabase Storage, which requires a signed-in
  /// cloud session. In local-only mode there is nowhere to host them.
  bool get imagesSupported => _cloudConfigured && _isSignedIn;

  /// Uploads image [bytes] to cloud storage and returns the public URL to embed
  /// in the note's Markdown. Throws if cloud storage is unavailable.
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

  Future<void> applyReminderToNote({
    required NoteItem note,
    required DateTime reminderAt,
  }) async {
    final NoteItem updated = note.copyWith(reminderAt: reminderAt);
    await saveNote(updated);
    await _reminderService.scheduleReminder(
      noteId: updated.id,
      title: updated.title,
      body: updated.body,
      when: reminderAt,
    );
  }

  Future<void> clearReminder(NoteItem note) async {
    await saveNote(note.copyWith(clearReminder: true));
    await _reminderService.cancelReminder(note.id);
  }

  Future<void> appendSpeechToNote({
    required NoteItem note,
    required String recognizedWords,
  }) async {
    final String merged = '${note.body}\n${recognizedWords.trim()}'.trim();
    await saveNote(note.copyWith(body: merged));
  }

  Future<void> startSpeechCapture({
    required void Function(SpeechCaptureResult result) onResult,
  }) {
    return _speechService.startListening(onResult: onResult);
  }

  Future<void> stopSpeechCapture() {
    return _speechService.stopListening();
  }

  Future<void> appendOcrTextToNote({
    required NoteItem note,
    required String imagePath,
  }) async {
    final String extracted =
        await _ocrService.extractTextFromImagePath(imagePath);
    if (extracted.trim().isEmpty) {
      return;
    }

    final String merged = '${note.body}\n\n[OCR]\n${extracted.trim()}'.trim();
    await saveNote(note.copyWith(body: merged));
  }

  /// Extracts text from an image without mutating the note. The rich text
  /// editor uses this to insert OCR results directly into the document.
  Future<String> extractTextFromImage(String imagePath) {
    return _ocrService.extractTextFromImagePath(imagePath);
  }

  bool get ocrSupported => _ocrService.isSupported;

  // ---------------------------------------------------------------------------
  // AI (Claude) assistance
  // ---------------------------------------------------------------------------

  bool get aiAvailable => _aiService.isAvailable;

  Future<String> summarizeText(String text) => _aiService.summarize(text);

  Future<String> cleanUpText(String text) => _aiService.cleanUp(text);

  Future<void> suggestAndAddTags(NoteItem note) async {
    final List<String> suggested = await _aiService.suggestTags(note.body);
    if (suggested.isEmpty) {
      return;
    }
    final Set<String> merged = <String>{...note.tags, ...suggested};
    await saveNote(note.copyWith(tags: merged.toList(growable: false)));
  }

  Future<void> shareNote(NoteItem note) {
    return _shareService.shareNoteWithImages(
      title: note.title,
      body: note.body,
      imagePaths: note.imagePaths,
    );
  }

  Future<void> exportNoteAsTxt(NoteItem note) {
    return _shareService.exportNoteAsTxt(note);
  }

  Future<void> exportNoteAsPdf(NoteItem note) {
    return _shareService.exportNoteAsPdf(note);
  }

  Future<void> exportAllDataBackup() {
    return _shareService.exportBackupJson(
      notes: _notes,
      folders: _folders,
      templates: _templates,
    );
  }

  Future<NoteItem> quickCaptureNote(String text) async {
    final String trimmed = text.trim();
    final String title =
        trimmed.isEmpty ? 'Quick Capture' : trimmed.split('\n').first.trim();

    final NoteItem note = NoteItem(
      id: _uuid.v4(),
      ownerId: _activeUserId,
      folderId: _selectedFolderId ?? _defaultFolderId,
      title: title.length > 60 ? '${title.substring(0, 60)}...' : title,
      body: trimmed,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      reminderAt: null,
      imagePaths: const <String>[],
      tags: const <String>[],
      localOnly: true,
      revision: 0,
      conflictGroupId: null,
    );

    await _upsertNote(note);
    return note;
  }

  Future<void> deleteNote(String noteId) async {
    final NoteItem? note = getNoteById(noteId);
    if (note == null) {
      return;
    }

    await moveToTrash(note);
  }

  Future<void> permanentlyDeleteNote(String noteId) async {
    await _localStoreService.deleteNote(noteId);
    await _localStoreService.clearNoteVersions(noteId);
    await _syncService.queueNoteDelete(noteId);
    await _refreshData();
  }

  List<NoteItem> getVersionHistory(String noteId) {
    return _localStoreService.readNoteVersions(noteId);
  }

  Future<void> restoreVersion({
    required String noteId,
    required NoteItem version,
  }) async {
    final NoteItem restored = version.copyWith(
      id: noteId,
      updatedAt: DateTime.now().toUtc(),
      localOnly: true,
      revision: version.revision + 1,
      isDeleted: false,
      clearDeletedAt: true,
    );

    await _upsertNote(restored);
  }

  Future<void> setTheme(String themeId) {
    return _themeController.setTheme(themeId);
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void setDateFilter({DateTime? startDate, DateTime? endDate}) {
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    notifyListeners();
  }

  void setHasImageFilter(bool value) {
    _hasImageFilter = value;
    notifyListeners();
  }

  void setShowArchived(bool value) {
    _showArchived = value;
    notifyListeners();
  }

  Future<void> selectFolder(String? folderId) async {
    if (folderId == null) {
      _selectedFolderId = null;
      notifyListeners();
      return;
    }

    if (isFolderLocked(folderId)) {
      final bool unlocked = await unlockFolder(folderId);
      if (!unlocked) {
        return;
      }
    }

    _selectedFolderId = folderId;
    notifyListeners();
  }

  Future<void> saveCustomTemplate({
    required String title,
    required String body,
  }) async {
    final TemplateItem template = TemplateItem(
      id: _uuid.v4(),
      title: title.trim(),
      body: body.trim(),
      ownerId: _activeUserId,
      isBuiltIn: false,
    );

    await _templateService.saveCustomTemplate(template);
    await _refreshData();
  }

  Future<void> importMarketplaceTemplate(TemplateItem template) async {
    final TemplateItem copy = TemplateItem(
      id: _uuid.v4(),
      title: template.title,
      body: template.body,
      ownerId: _activeUserId,
      isBuiltIn: false,
    );

    await _templateService.saveCustomTemplate(copy);
    await _refreshData();
  }

  Future<bool> syncNow() async {
    final bool synced = await _syncService.syncPendingMutations();
    if (synced) {
      await _refreshData();
    }
    return synced;
  }

  Future<void> _upsertNote(NoteItem note) async {
    await _localStoreService.upsertNote(note);
    await _localStoreService.appendNoteVersion(note);
    await _syncService.queueNoteUpsert(note);
    await _refreshData();
  }

  Future<void> _refreshData() async {
    final String ownerId = _activeUserId;

    _folders = _localStoreService.readFoldersForUser(ownerId);
    if (_folders.isEmpty) {
      final FolderItem inbox = FolderItem(
        id: _uuid.v4(),
        ownerId: ownerId,
        name: 'Inbox',
        parentId: null,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _localStoreService.upsertFolder(inbox);
      await _syncService.queueFolderUpsert(inbox);
      _folders = <FolderItem>[inbox];
    }

    _notes = _localStoreService.readNotesForUser(ownerId);
    _templates = await _templateService.getTemplatesForUser(ownerId);

    if (_selectedFolderId != null &&
        _folders.every((FolderItem folder) => folder.id != _selectedFolderId)) {
      _selectedFolderId = null;
    }

    _selectedFolderId ??= _defaultFolderId;
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    _isBusy = true;
    notifyListeners();

    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String get _activeUserId =>
      _cloudConfigured ? _authService.currentUserId : 'local-offline-user';

  String get _defaultFolderId {
    if (_folders.isNotEmpty) {
      return _folders.first.id;
    }
    return 'inbox';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _syncTimer?.cancel();
    unawaited(_authService.dispose());
    unawaited(_ocrService.dispose());
    _aiService.dispose();
    super.dispose();
  }
}
