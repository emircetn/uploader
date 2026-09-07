## 1.0.0

First stable release. The API and the `pubspec.yaml` schema are now considered
stable and will follow semantic versioning.

- **BREAKING CHANGE**: Minimum Dart SDK is now 3.9.0 (Flutter 3.35), required by the updated Google APIs dependencies
- **BREAKING CHANGE**: The package is now a pure Dart package and no longer depends on the Flutter SDK. It can still be used as a `dev_dependency` in Flutter projects exactly as before
- Registered `uploader` as an executable, so it can be run with `dart run uploader`

### Dependencies

- Updated `googleapis` to 17.x and `googleapis_auth` to 2.x
- Widened the `dio` constraint to `^5.0.0` and added `args: ^2.5.0`, deliberately loose so the package does not clash with the host app's own pins

### Command line

- The process now exits with a non-zero status when the upload fails, so it can be used as a CI step
- Added `--yes` to skip the confirmation prompt, `--dry-run` to print every command without running it, plus `--help`

### Build parameters

- Added `appDistributionExtraBuildParameters` and `storeExtraBuildParameters`, applied on top of `extraBuildParameters` for that target's builds only. A flag meant for testers no longer has to reach the store binary
- Each target is now built separately on Android. Previously a single app bundle was produced and sent to both App Distribution and the Play Console, so the two could not differ. With `uploadType: all` in `abb` mode this now produces two bundles
- `uploadType: appDistribution` with `androidBuildType: apk` no longer builds an app bundle nobody uses
- The confirmation screen now prints the resolved build parameters per target before anything is built

### Play Console

- Added `releaseStatus` (`completed` or `draft`), so a release can be staged in the Play Console instead of going live immediately. Previously every release was published as `completed`

### Firebase App Distribution

- Added `androidGroups` and `iosGroups` for distributing to tester groups instead of listing individual testers

### Reliability

- Upload steps are now retried on failure, twice by default, configurable with `uploadRetryCount`. Builds are not retried
- Fixed `extraBuildParameters` being passed to `flutter build` as a single comma joined argument, which silently broke any configuration with more than one parameter
- Fixed the APK path resolving to the AAB output, which uploaded the wrong artifact when `androidBuildType` was `apk`
- Fixed a run reporting success when App Distribution was requested but the Firebase app id could not be resolved, so nothing was uploaded. The check now runs before the build instead of after
- `pubspec.yaml` is now parsed with the `yaml` package instead of line matching, which mistook any line containing `name:` for the project name and failed on versions without a build number
- Merged the duplicated `constant`/`constants` folders and added unit tests

## 0.1.4

- Android package name is now automatically retrieved, removing the need to provide it as a parameter
- Fixed a bug that occurred during the upload process to Firebase App Distribution

## 0.1.3

- Update readme

## 0.1.2

- Update readme

## 0.1.1

- **BREAKING CHANGE**: Replaced `androidConfig` and `iosConfig` with `playStoreConfig` and `testFlightConfig` for better platform-specific configuration clarity
- Enhanced project details display for better readability
- Added TestFlight and Play Store configuration improvements

## 0.1.0

- Added log system support to enable logging functionality.
- Added parallel upload support for faster upload processes.
- Updated config parameter types for improved flexibility and clarity.

## 0.0.9

- Update readme and packages

## 0.0.8

- Update readme

## 0.0.7

- removed unnecessary use of 'only' from enums

## 0.0.6

- Update readme

## 0.0.5

- Update description

## 0.0.4

- Add example

## 0.0.3

- Update readme

## 0.0.2

- All project files moved to the src folder

## 0.0.1

- First Release
