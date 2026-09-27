import 'package:flutter/material.dart';

/// A colour a note can be tagged with. Each has a light and a dark variant so
/// cards stay soft on paper-white backgrounds and never glare in dark mode.
class NoteColor {
  const NoteColor(this.id, this.name, this.light, this.dark);

  final String id;
  final String name;
  final Color light;
  final Color dark;

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

class NoteColors {
  const NoteColors._();

  static const List<NoteColor> all = <NoteColor>[
    NoteColor('coral', 'Coral', Color(0xFFF8CEC5), Color(0xFF5A2D29)),
    NoteColor('peach', 'Peach', Color(0xFFF9DBBE), Color(0xFF5A3C22)),
    NoteColor('sand', 'Sand', Color(0xFFF5E9B8), Color(0xFF514823)),
    NoteColor('sage', 'Sage', Color(0xFFD7E9CC), Color(0xFF2F4830)),
    NoteColor('mint', 'Mint', Color(0xFFC8E7DE), Color(0xFF214842)),
    NoteColor('sky', 'Sky', Color(0xFFD3E4F1), Color(0xFF233F55)),
    NoteColor('lavender', 'Lavender', Color(0xFFE0D7EF), Color(0xFF3D3256)),
    NoteColor('rose', 'Rose', Color(0xFFF2D3E0), Color(0xFF543145)),
    NoteColor('clay', 'Clay', Color(0xFFE6DCCE), Color(0xFF453D34)),
    NoteColor('slate', 'Slate', Color(0xFFDDE0E4), Color(0xFF33383E)),
  ];

  static NoteColor? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final NoteColor color in all) {
      if (color.id == id) {
        return color;
      }
    }
    return null;
  }

  /// Background for a note card or editor, or null for the default surface.
  static Color? backgroundFor(String? id, Brightness brightness) =>
      byId(id)?.resolve(brightness);
}
