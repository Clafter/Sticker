// ignore_for_file: prefer_initializing_formals
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/app_environment.dart';

abstract class SettingsStore {
  bool get onboardingComplete;
  Future<void> setOnboardingComplete();

  String? get giphyApiKey;
  Future<void> setGiphyApiKey(String? key);

  String? get klipyApiKey;
  Future<void> setKlipyApiKey(String? key);

  String? get apifyApiToken;
  Future<void> setApifyApiToken(String? token);

  String get gifProvider;
  Future<void> setGifProvider(String provider);
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore({
    bool onboardingComplete = false,
    String? giphyApiKey,
    String? klipyApiKey,
    String? apifyApiToken,
    String gifProvider = 'giphy',
  }) : _onboardingComplete = onboardingComplete,
       _giphyApiKey = giphyApiKey,
       _klipyApiKey = klipyApiKey,
       _apifyApiToken = apifyApiToken,
       _gifProvider = gifProvider;

  bool _onboardingComplete;
  String? _giphyApiKey;
  String? _klipyApiKey;
  String? _apifyApiToken;
  String _gifProvider;

  @override
  bool get onboardingComplete => _onboardingComplete;

  @override
  Future<void> setOnboardingComplete() async {
    _onboardingComplete = true;
  }

  @override
  String? get giphyApiKey => _giphyApiKey;

  @override
  Future<void> setGiphyApiKey(String? key) async {
    _giphyApiKey = key?.trim().isEmpty == true ? null : key?.trim();
  }

  @override
  String? get klipyApiKey => _klipyApiKey;

  @override
  Future<void> setKlipyApiKey(String? key) async {
    _klipyApiKey = key?.trim().isEmpty == true ? null : key?.trim();
  }

  @override
  String? get apifyApiToken => _apifyApiToken;

  @override
  Future<void> setApifyApiToken(String? token) async {
    _apifyApiToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  @override
  String get gifProvider => _gifProvider;

  @override
  Future<void> setGifProvider(String provider) async {
    _gifProvider = provider;
  }
}

class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore(this.box);

  static const boxName = 'app_settings';
  static const onboardingKey = 'onboardingComplete';
  static const giphyApiKeyHiveKey = 'giphyApiKey';
  static const klipyApiKeyHiveKey = 'klipyApiKey';
  static const apifyApiTokenHiveKey = 'apifyApiToken';
  static const gifProviderHiveKey = 'gifProvider';

  final Box<dynamic> box;

  static Future<HiveSettingsStore> open({String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box<dynamic>(boxName)
        : await Hive.openBox<dynamic>(boxName);
    final store = HiveSettingsStore(box);
    // One-time seed: migrate compile-time dart-defines into Hive on first run
    // so users who received a pre-keyed build don't need to re-enter their keys.
    await store._seedFromDartDefines();
    return store;
  }

  Future<void> _seedFromDartDefines() async {
    if (!box.containsKey(giphyApiKeyHiveKey) &&
        AppEnvironment.giphyApiKey.isNotEmpty) {
      await box.put(giphyApiKeyHiveKey, AppEnvironment.giphyApiKey);
    }
    if (!box.containsKey(klipyApiKeyHiveKey) &&
        AppEnvironment.klipyApiKey.isNotEmpty) {
      await box.put(klipyApiKeyHiveKey, AppEnvironment.klipyApiKey);
    }
    if (!box.containsKey(apifyApiTokenHiveKey) &&
        AppEnvironment.apifyApiToken.isNotEmpty) {
      await box.put(apifyApiTokenHiveKey, AppEnvironment.apifyApiToken);
    }
  }

  @override
  bool get onboardingComplete =>
      box.get(onboardingKey, defaultValue: false) == true;

  @override
  Future<void> setOnboardingComplete() async {
    await box.put(onboardingKey, true);
  }

  @override
  String? get giphyApiKey {
    final stored = box.get(giphyApiKeyHiveKey)?.toString().trim();
    return stored?.isEmpty == true ? null : stored;
  }

  @override
  Future<void> setGiphyApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await box.delete(giphyApiKeyHiveKey);
    } else {
      await box.put(giphyApiKeyHiveKey, trimmed);
    }
  }

  @override
  String? get klipyApiKey {
    final stored = box.get(klipyApiKeyHiveKey)?.toString().trim();
    return stored?.isEmpty == true ? null : stored;
  }

  @override
  Future<void> setKlipyApiKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await box.delete(klipyApiKeyHiveKey);
    } else {
      await box.put(klipyApiKeyHiveKey, trimmed);
    }
  }

  @override
  String? get apifyApiToken {
    final stored = box.get(apifyApiTokenHiveKey)?.toString().trim();
    return stored?.isEmpty == true ? null : stored;
  }

  @override
  Future<void> setApifyApiToken(String? token) async {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await box.delete(apifyApiTokenHiveKey);
    } else {
      await box.put(apifyApiTokenHiveKey, trimmed);
    }
  }

  @override
  String get gifProvider =>
      box.get(gifProviderHiveKey, defaultValue: 'giphy')?.toString() ?? 'giphy';

  @override
  Future<void> setGifProvider(String provider) async {
    await box.put(gifProviderHiveKey, provider);
  }
}

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return InMemorySettingsStore();
});

// Notifier that wraps the store and can be invalidated to force widget rebuilds
// after API key changes. Widgets that display key status should watch this.
final apiKeySettingsProvider =
    NotifierProvider<_ApiKeyNotifier, _ApiKeyState>(_ApiKeyNotifier.new);

class _ApiKeyState {
  const _ApiKeyState({
    this.giphyApiKey,
    this.klipyApiKey,
    this.apifyApiToken,
  });

  final String? giphyApiKey;
  final String? klipyApiKey;
  final String? apifyApiToken;
}

class _ApiKeyNotifier extends Notifier<_ApiKeyState> {
  @override
  _ApiKeyState build() {
    final store = ref.watch(settingsStoreProvider);
    return _ApiKeyState(
      giphyApiKey: store.giphyApiKey,
      klipyApiKey: store.klipyApiKey,
      apifyApiToken: store.apifyApiToken,
    );
  }

  Future<void> setGiphyApiKey(String? key) async {
    await ref.read(settingsStoreProvider).setGiphyApiKey(key);
    state = _ApiKeyState(
      giphyApiKey: ref.read(settingsStoreProvider).giphyApiKey,
      klipyApiKey: state.klipyApiKey,
      apifyApiToken: state.apifyApiToken,
    );
  }

  Future<void> setKlipyApiKey(String? key) async {
    await ref.read(settingsStoreProvider).setKlipyApiKey(key);
    state = _ApiKeyState(
      giphyApiKey: state.giphyApiKey,
      klipyApiKey: ref.read(settingsStoreProvider).klipyApiKey,
      apifyApiToken: state.apifyApiToken,
    );
  }

  Future<void> setApifyApiToken(String? token) async {
    await ref.read(settingsStoreProvider).setApifyApiToken(token);
    state = _ApiKeyState(
      giphyApiKey: state.giphyApiKey,
      klipyApiKey: state.klipyApiKey,
      apifyApiToken: ref.read(settingsStoreProvider).apifyApiToken,
    );
  }
}
