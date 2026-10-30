class EnvironmentConfigurationException implements Exception {
  const EnvironmentConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppEnvironment {
  const AppEnvironment._();

  static const giphyApiKey = String.fromEnvironment('GIPHY_API_KEY');
  static const klipyApiKey = String.fromEnvironment('KLIPY_API_KEY');
  static const apifyApiToken = String.fromEnvironment('APIFY_API_TOKEN');

  // Keys are optional at startup — users can enter them in Settings → API Keys.
  // This method is kept for test injection; main() no longer calls it.
  static void validateRequired({
    String giphyKey = giphyApiKey,
    String apifyToken = apifyApiToken,
  }) {
    final missing = <String>[
      if (giphyKey.trim().isEmpty) 'GIPHY_API_KEY',
      if (apifyToken.trim().isEmpty) 'APIFY_API_TOKEN',
    ];
    if (missing.isEmpty) return;

    throw EnvironmentConfigurationException(
      'Missing required environment variables: ${missing.join(', ')}. '
      'Provide them with --dart-define or add them in Settings → API Keys.',
    );
  }
}
