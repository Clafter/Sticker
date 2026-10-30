import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_store.dart';

enum GifProvider { giphy, klipy }

extension GifProviderLabel on GifProvider {
  String get key => name; // 'giphy' or 'klipy'
}

GifProvider _fromString(String value) {
  return GifProvider.values.firstWhere(
    (p) => p.name == value,
    orElse: () => GifProvider.giphy,
  );
}

class GifProviderNotifier extends Notifier<GifProvider> {
  @override
  GifProvider build() {
    final store = ref.watch(settingsStoreProvider);
    return _fromString(store.gifProvider);
  }

  Future<void> setProvider(GifProvider provider) async {
    await ref.read(settingsStoreProvider).setGifProvider(provider.name);
    state = provider;
  }
}

final gifProviderProvider =
    NotifierProvider<GifProviderNotifier, GifProvider>(GifProviderNotifier.new);
