import 'package:flutter/material.dart';

/// A selectable accent theme.
///
/// Most themes are a single seed colour from which Material 3 generates
/// harmonised light and dark schemes. The default "Secretary" theme is hand
/// tuned instead: warm paper neutrals and charcoal ink taken from the app's
/// secretary-bird icon, with the bird's orange eye as the accent.
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.seed,
    this.handTuned = false,
  });

  final String id;
  final String name;
  final String description;
  final Color seed;

  /// True when the scheme comes from [secretaryScheme] rather than the seed.
  final bool handTuned;
}

const String kDefaultThemeId = 'secretary';

/// The brand orange from the app icon. Used as-is for accents on dark
/// surfaces; text-bearing surfaces use the deeper [_ink] tones for contrast.
const Color kBrandOrange = Color(0xFFEE7B2E);
const Color kBrandCharcoal = Color(0xFF262626);

const List<AppTheme> kThemePresets = <AppTheme>[
  AppTheme(
    id: 'secretary',
    name: 'Secretary',
    description: 'Warm paper, charcoal ink and a bold orange accent.',
    seed: kBrandOrange,
    handTuned: true,
  ),
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

/// The hand-tuned default scheme.
///
/// Light primary #B8520F sits at about 4.9:1 against white, so white labels on
/// filled buttons meet WCAG AA. Dark mode uses a lighter orange on charcoal.
ColorScheme secretaryScheme(Brightness brightness) {
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: kBrandOrange,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  if (brightness == Brightness.light) {
    return base.copyWith(
      primary: const Color(0xFFB8520F),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE2CF),
      onPrimaryContainer: const Color(0xFF3A1903),
      secondary: const Color(0xFF6E6154),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFF1E6DA),
      onSecondaryContainer: const Color(0xFF261B11),
      tertiary: const Color(0xFF3D6A61),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFD2EAE3),
      onTertiaryContainer: const Color(0xFF06201B),
      surface: const Color(0xFFFCFAF7),
      onSurface: const Color(0xFF1F1D1A),
      onSurfaceVariant: const Color(0xFF5E5850),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F4EF),
      surfaceContainer: const Color(0xFFF2EEE8),
      surfaceContainerHigh: const Color(0xFFECE7E0),
      surfaceContainerHighest: const Color(0xFFE5DFD7),
      surfaceDim: const Color(0xFFDDD7CE),
      surfaceBright: const Color(0xFFFCFAF7),
      outline: const Color(0xFF8D867C),
      outlineVariant: const Color(0xFFDFD8CE),
      inverseSurface: kBrandCharcoal,
      onInverseSurface: const Color(0xFFF4EFE9),
      inversePrimary: const Color(0xFFFFB585),
      surfaceTint: Colors.transparent,
    );
  }

  return base.copyWith(
    primary: const Color(0xFFFFA266),
    onPrimary: const Color(0xFF3A1903),
    primaryContainer: const Color(0xFF6E3309),
    onPrimaryContainer: const Color(0xFFFFDCC6),
    secondary: const Color(0xFFD5C4B3),
    onSecondary: const Color(0xFF3A2E23),
    secondaryContainer: const Color(0xFF3D342C),
    onSecondaryContainer: const Color(0xFFF1E1D0),
    tertiary: const Color(0xFF9FD0C4),
    onTertiary: const Color(0xFF05372F),
    tertiaryContainer: const Color(0xFF214E46),
    onTertiaryContainer: const Color(0xFFBDEDE0),
    surface: const Color(0xFF171614),
    onSurface: const Color(0xFFEDE8E2),
    onSurfaceVariant: const Color(0xFFB9B1A7),
    surfaceContainerLowest: const Color(0xFF100F0E),
    surfaceContainerLow: const Color(0xFF1D1C1A),
    surfaceContainer: const Color(0xFF22201E),
    surfaceContainerHigh: const Color(0xFF2B2926),
    surfaceContainerHighest: const Color(0xFF35322F),
    surfaceDim: const Color(0xFF171614),
    surfaceBright: const Color(0xFF3B3835),
    outline: const Color(0xFF8B837A),
    outlineVariant: const Color(0xFF3E3A35),
    inverseSurface: const Color(0xFFEDE8E2),
    onInverseSurface: const Color(0xFF2B2926),
    inversePrimary: const Color(0xFFB8520F),
    surfaceTint: Colors.transparent,
  );
}
