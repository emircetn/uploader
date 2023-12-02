# Installation
```sh
flutter pub add --dev uploader
```

# How to use

- Add config to `pubspec.yaml`

```yaml
uploader:
  platform: all  # iosOnly, androidOnly, all
  uploadType: all # appDistributionOnly, storeOnly, all
  iosConfig:
    path: ios_deploy_config.json # must include auth_key and issuer_id
  androidConfig:
    path: android_deploy_config.json # must include client_email, client_id, private_key
    track: internal # internal, alpha, beta
    packageName: "com.package.name"
    skslPath: null 
  appDistributionConfig:
    androidBuildType : abb # abb, apk 
    androidTesters : null 
    iosTesters : [
      "tester1@gmail.com", 
      "tester2@gmail.com",
    ]
    releaseNotes: [
      "app icon updated"
    ]
  extraBuildParameters: null
```
After configured, now you can run uploader
  
```sh
flutter pub run uploader
```

