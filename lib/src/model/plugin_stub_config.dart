import 'package:uploader/src/enum/enums.dart';

/// Packages a run swaps for trimmed copies: plugins whose native side is left
/// out of the builds while their Dart API stays available so every package
/// that imports them still compiles, and packages whose unused assets or
/// fonts are left out of the bundle.
class PluginStubConfig {
  final List<String> all;
  final List<String> ios;
  final List<String> android;

  /// Glob patterns per package, relative to the package root, for asset files
  /// the bundle must not contain.
  final Map<String, List<String>> prunedAssets;

  /// Font families per package the bundle must not contain.
  final Map<String, List<String>> prunedFonts;

  /// Also stubs, per platform, every plugin a code size analysis build finds
  /// no Dart code reaching.
  final bool auto;

  /// Plugins [auto] never stubs, for those the app uses in a way the analysis
  /// cannot see.
  final List<String> keep;

  const PluginStubConfig({
    this.all = const [],
    this.ios = const [],
    this.android = const [],
    this.prunedAssets = const {},
    this.prunedFonts = const {},
    this.auto = false,
    this.keep = const [],
  });

  bool get isEmpty =>
      strippedPlatforms.isEmpty && prunedAssets.isEmpty && prunedFonts.isEmpty;

  /// Every package that gets a trimmed copy, for any reason.
  Set<String> get packageNames => {
    ...strippedPlatforms.keys,
    ...prunedAssets.keys,
    ...prunedFonts.keys,
  };

  /// The platform each package is removed from. A package listed under both
  /// `ios` and `android` is removed from both, the same as listing it under
  /// `all`.
  Map<String, AppPlatform> get strippedPlatforms {
    final platforms = <String, AppPlatform>{};

    for (final name in ios) {
      platforms[name] = AppPlatform.ios;
    }
    for (final name in android) {
      platforms[name] = platforms[name] == AppPlatform.ios
          ? AppPlatform.all
          : AppPlatform.android;
    }
    for (final name in all) {
      platforms[name] = AppPlatform.all;
    }

    return platforms;
  }
}
