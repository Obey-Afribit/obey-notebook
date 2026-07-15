enum SyncOperation {
  upsertNote,
  deleteNote,
  upsertFolder,
  deleteFolder,
}

class SyncMutation {
  const SyncMutation({
    required this.id,
    required this.operation,
    required this.entityId,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final SyncOperation operation;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation': operation.name,
      'entityId': entityId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SyncMutation.fromMap(Map<String, dynamic> map) {
    return SyncMutation(
      id: map['id'] as String,
      operation: SyncOperation.values.firstWhere(
        (SyncOperation op) => op.name == map['operation'],
        orElse: () => SyncOperation.upsertNote,
      ),
      entityId: map['entityId'] as String,
      payload: (map['payload'] as Map<dynamic, dynamic>? ?? const {})
          .map((dynamic key, dynamic value) => MapEntry(key.toString(), value)),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
