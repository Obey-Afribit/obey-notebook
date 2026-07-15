class ThemePack {
  const ThemePack({
    required this.id,
    required this.name,
    required this.seedColorHex,
    required this.backgroundTopHex,
    required this.backgroundBottomHex,
    required this.accentHex,
    this.description = '',
    this.isBuiltIn = false,
    this.downloadUrl,
  });

  final String id;
  final String name;
  final String description;
  final String seedColorHex;
  final String backgroundTopHex;
  final String backgroundBottomHex;
  final String accentHex;
  final bool isBuiltIn;
  final String? downloadUrl;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'seedColorHex': seedColorHex,
      'backgroundTopHex': backgroundTopHex,
      'backgroundBottomHex': backgroundBottomHex,
      'accentHex': accentHex,
      'isBuiltIn': isBuiltIn,
      'downloadUrl': downloadUrl,
    };
  }

  factory ThemePack.fromMap(Map<String, dynamic> map) {
    return ThemePack(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      seedColorHex: map['seedColorHex'] as String,
      backgroundTopHex: map['backgroundTopHex'] as String,
      backgroundBottomHex: map['backgroundBottomHex'] as String,
      accentHex: map['accentHex'] as String,
      isBuiltIn: map['isBuiltIn'] as bool? ?? false,
      downloadUrl: map['downloadUrl'] as String?,
    );
  }
}
