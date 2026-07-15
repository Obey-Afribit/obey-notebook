import 'package:flutter/material.dart';

Color colorFromHex(String hex) {
  final String normalized = hex.replaceAll('#', '').trim();
  if (normalized.length == 6) {
    return Color(int.parse('FF$normalized', radix: 16));
  }
  if (normalized.length == 8) {
    return Color(int.parse(normalized, radix: 16));
  }
  return const Color(0xFF3DD6D0);
}
