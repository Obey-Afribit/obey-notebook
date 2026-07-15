class TemplateItem {
  const TemplateItem({
    required this.id,
    required this.title,
    required this.body,
    this.ownerId,
    this.isBuiltIn = false,
  });

  final String id;
  final String title;
  final String body;
  final String? ownerId;
  final bool isBuiltIn;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'ownerId': ownerId,
      'isBuiltIn': isBuiltIn,
    };
  }

  factory TemplateItem.fromMap(Map<String, dynamic> map) {
    return TemplateItem(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      ownerId: map['ownerId'] as String?,
      isBuiltIn: map['isBuiltIn'] as bool? ?? false,
    );
  }
}
