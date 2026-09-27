class NoteItem {
  const NoteItem({
    required this.id,
    required this.ownerId,
    required this.folderId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.imagePaths,
    required this.tags,
    required this.localOnly,
    required this.revision,
    this.isPinned = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.deletedAt,
    this.reminderAt,
    this.conflictGroupId,
    this.colorId,
  });

  final String id;
  final String ownerId;
  final String folderId;
  final String title;

  /// Note content as Markdown source. Rendered in the editor's reading view
  /// and used directly for search, card previews, export, sharing, and AI.
  final String body;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reminderAt;
  final List<String> imagePaths;
  final List<String> tags;
  final bool localOnly;
  final int revision;
  final bool isPinned;
  final bool isArchived;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? conflictGroupId;

  /// Key into [NoteColors]; null means the default surface.
  final String? colorId;

  /// Title shown in the UI. Older notes stored the literal "Untitled note".
  String get displayTitle {
    final String trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == 'Untitled note') {
      return '';
    }
    return trimmed;
  }

  bool get isEmpty => displayTitle.isEmpty && body.trim().isEmpty;

  NoteItem copyWith({
    String? id,
    String? ownerId,
    String? folderId,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reminderAt,
    bool clearReminder = false,
    List<String>? imagePaths,
    List<String>? tags,
    bool? localOnly,
    int? revision,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? conflictGroupId,
    String? colorId,
    bool clearColor = false,
  }) {
    return NoteItem(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      imagePaths: imagePaths ?? this.imagePaths,
      tags: tags ?? this.tags,
      localOnly: localOnly ?? this.localOnly,
      revision: revision ?? this.revision,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      conflictGroupId: conflictGroupId ?? this.conflictGroupId,
      colorId: clearColor ? null : (colorId ?? this.colorId),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'folderId': folderId,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'reminderAt': reminderAt?.toIso8601String(),
      'imagePaths': imagePaths,
      'tags': tags,
      'localOnly': localOnly,
      'revision': revision,
      'isPinned': isPinned,
      'isArchived': isArchived,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'conflictGroupId': conflictGroupId,
      'colorId': colorId,
    };
  }

  factory NoteItem.fromMap(Map<String, dynamic> map) {
    return NoteItem(
      id: map['id'] as String,
      ownerId: map['ownerId'] as String? ?? '',
      folderId: map['folderId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      reminderAt: map['reminderAt'] == null
          ? null
          : DateTime.parse(map['reminderAt'] as String),
      imagePaths: (map['imagePaths'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      tags: (map['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      localOnly: map['localOnly'] as bool? ?? true,
      revision: map['revision'] as int? ?? 0,
      isPinned: map['isPinned'] as bool? ?? false,
      isArchived: map['isArchived'] as bool? ?? false,
      isDeleted: map['isDeleted'] as bool? ?? false,
      deletedAt: map['deletedAt'] == null
          ? null
          : DateTime.parse(map['deletedAt'] as String),
      conflictGroupId: map['conflictGroupId'] as String?,
      colorId: map['colorId'] as String?,
    );
  }
}
