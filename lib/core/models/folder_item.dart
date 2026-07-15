class FolderItem {
  const FolderItem({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  FolderItem copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? parentId,
    bool clearParent = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FolderItem(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'name': name,
      'parentId': parentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory FolderItem.fromMap(Map<String, dynamic> map) {
    return FolderItem(
      id: map['id'] as String,
      ownerId: map['ownerId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      parentId: map['parentId'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
