# Installation

```sh
flutter pub add --dev uploader
```

# How to use

- Add config to `pubspec.yaml`

```yaml
uploader:
  platform: all # ios, android, all
  uploadType: all # appDistribution, store, all
  testFlightConfig:
    path: ios/deploy_config.json # must include auth_key and issuer_id
  playStoreConfig:
    path: android/deploy_config.json # must include client_email, client_id, private_key
    track: internal # internal, alpha, beta
    skslPath: android/sksl.json
  appDistributionConfig:
    androidBuildType: abb # abb, apk
    androidTesters:
      path: android/testers.txt
    iosTesters:
      url: https://testers.txt
    releaseNotesPath: release_notes.txt
  useParallelUpload: true # default:true
  enableLogFileCreation: false # default: false.
  extraBuildParameters: null
```

After configured, now you can run uploader

```sh
flutter pub run uploader
```
