import 'package:test/test.dart';
import 'package:uploader/src/helper/plugin_allowlist_helper.dart';

void main() {
  final helper = PluginAllowlistHelper();

  final registered = helper.registeredPlugins(
    pluginsDependencies: {
      "plugins": {
        "ios": [
          {"name": "url_launcher_ios"},
          {"name": "adapty_flutter"},
        ],
        "android": [
          {"name": "url_launcher_android"},
        ],
        "macos": [
          {"name": "path_provider_foundation"},
        ],
      },
    },
    platformKeys: ["ios", "android"],
  );

  test('registered plugins are read per built platform, sorted', () {
    expect(registered, {
      "ios": ["adapty_flutter", "url_launcher_ios"],
      "android": ["url_launcher_android"],
    });
  });

  test('a plugin missing from the list is unexpected', () {
    expect(
      helper.unexpected(
        allowed: {
          "ios": ["url_launcher_ios"],
          "android": ["url_launcher_android"],
        },
        registered: registered,
      ),
      {
        "ios": ["adapty_flutter"],
      },
    );
  });

  test('a listed plugin no longer registered can be dropped', () {
    expect(
      helper.unregistered(
        allowed: {
          "ios": ["adapty_flutter", "url_launcher_ios", "workmanager"],
        },
        registered: registered,
      ),
      {
        "ios": ["workmanager"],
      },
    );
  });

  test('a platform without a list is unrecorded, not unexpected', () {
    final allowed = {
      "ios": ["adapty_flutter", "url_launcher_ios"],
    };

    expect(
      helper.unexpected(allowed: allowed, registered: registered),
      isEmpty,
    );
    expect(
      helper.unrecordedPlatforms(allowed: allowed, registered: registered),
      ["android"],
    );
  });

  test('the file round-trips', () {
    final encoded = helper.encode(registered);

    expect(encoded, startsWith("#"));
    expect(helper.decode(encoded), {
      "android": ["url_launcher_android"],
      "ios": ["adapty_flutter", "url_launcher_ios"],
    });
  });
}
