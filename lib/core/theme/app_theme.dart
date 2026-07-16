import 'package:flutter/material.dart';

/// A selectable theme. Each theme is a single seed color from which Material 3
/// generates fully harmonized light and dark color schemes, so every theme
/// works in both modes.
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.seed,
  });

  final String id;
  final String name;
  final String description;
  final Color seed;
}

/// The curated set of built-in themes.
const List<AppTheme> kThemePresets = <AppTheme>[
  AppTheme(
    id: 'aurora',
    name: 'Aurora',
    description: 'Cool teal with an iridescent glow.',
    seed: Color(0xFF17B3A6),
  ),
  AppTheme(
    id: 'indigo',
    name: 'Indigo',
    description: 'Calm, focused deep blue.',
    seed: Color(0xFF4F5BD5),
  ),
  AppTheme(
    id: 'violet',
    name: 'Violet',
    description: 'Royal purple with a creative edge.',
    seed: Color(0xFF7C4DFF),
  ),
  AppTheme(
    id: 'sunset',
    name: 'Sunset',
    description: 'Warm coral and amber tones.',
    seed: Color(0xFFF4623A),
  ),
  AppTheme(
    id: 'rose',
    name: 'Rose',
    description: 'Soft, elegant pink.',
    seed: Color(0xFFE8497C),
  ),
  AppTheme(
    id: 'forest',
    name: 'Forest',
    description: 'Grounded, natural green.',
    seed: Color(0xFF2E9E5B),
  ),
  AppTheme(
    id: 'ocean',
    name: 'Ocean',
    description: 'Bright, clear sky blue.',
    seed: Color(0xFF1E88E5),
  ),
  AppTheme(
    id: 'graphite',
    name: 'Graphite',
    description: 'Understated neutral slate.',
    seed: Color(0xFF5B6470),
  ),
];

const String kDefaultThemeId = 'aurora';
