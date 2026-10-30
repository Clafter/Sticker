import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../network/network_client.dart';
import '../state/settings_store.dart';
import '../storage/storage_utility.dart';

class KlipyException implements Exception {
  const KlipyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class KlipyRateLimitException extends KlipyException {
  KlipyRateLimitException([String? message])
    : super(message ?? serviceLocalizations.klipyRateLimitReached);
}

@immutable
class KlipySticker {
  const KlipySticker({
    required this.id,
    required this.title,
    required this.url,
    required this.width,
    required this.height,
  });

  final String id;
  final String title;
  final String url;
  final int width;
  final int height;

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 1;
    return (width / height).clamp(0.65, 1.5);
  }

  bool get animated => true;
}

class KlipyStickerPage {
  const KlipyStickerPage({required this.stickers, required this.nextCursor});

  final List<KlipySticker> stickers;
  final String? nextCursor;
}

typedef KlipyApiGet = Future<Response<dynamic>> Function(
  String path,
  Map<String, dynamic> queryParameters,
);

class KlipyService {
  KlipyService({
    NetworkClient? networkClient,
    Dio? dio,
    String apiKey = '',
    this.apiGet,
    Future<Directory> Function()? temporaryDirectory,
  }) : _networkClient = networkClient ?? NetworkClient(dio: dio),
       _apiKey = apiKey.trim(),
       _temporaryDirectory =
           temporaryDirectory ?? (() => getStickrTemporaryDirectory());

  static const baseUrl = 'https://api.klipy.com';
  static const searchEndpoint = '$baseUrl/v2/search';
  static const featuredEndpoint = '$baseUrl/v2/featured';
  static const pageSize = 50;
  static const _mediaFilter = 'webp';

  final NetworkClient _networkClient;
  final String _apiKey;
  final KlipyApiGet? apiGet;
  final Future<Directory> Function() _temporaryDirectory;

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<KlipyStickerPage> fetchFeatured({
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (!hasApiKey) {
      throw KlipyException(serviceLocalizations.klipyFeaturedUnavailable);
    }

    final parameters = <String, dynamic>{
      'key': _apiKey,
      'limit': pageSize,
      'media_filter': _mediaFilter,
      if (cursor != null) 'pos': cursor,
    };

    return _fetchPage(
      endpoint: featuredEndpoint,
      parameters: parameters,
      fallbackMessage: serviceLocalizations.klipyRequestFailed,
      cancelToken: cancelToken,
    );
  }

  Future<KlipyStickerPage> search(
    String query, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final term = query.trim();
    if (term.isEmpty) {
      throw KlipyException(serviceLocalizations.klipySearchRequired);
    }
    if (!hasApiKey) {
      throw KlipyException(serviceLocalizations.klipySearchUnavailable);
    }

    return _fetchPage(
      endpoint: searchEndpoint,
      parameters: <String, dynamic>{
        'key': _apiKey,
        'q': term,
        'limit': pageSize,
        'media_filter': _mediaFilter,
        if (cursor != null) 'pos': cursor,
      },
      fallbackMessage: serviceLocalizations.couldNotSearchKlipy,
      cancelToken: cancelToken,
    );
  }

  Future<File> downloadSticker({
    required String id,
    required String url,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw KlipyException(serviceLocalizations.invalidStickerDownloadUrl);
    }

    final directory = await _temporaryDirectory();
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final extension = uri.path.toLowerCase().endsWith('.webp') ? 'webp' : 'gif';
    final file = File(
      '${directory.path}${Platform.pathSeparator}klipy_${safeId.isEmpty ? 'sticker' : safeId}_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    try {
      await _networkClient.download(url, file.path, cancelToken: cancelToken);
      if (!await file.exists() || await file.length() == 0) {
        throw KlipyException(serviceLocalizations.giphyEmptySticker);
      }
      return file;
    } on KlipyException {
      rethrow;
    } on NetworkFailure catch (error) {
      if (await file.exists()) await file.delete();
      throw _fromNetwork(error);
    } on DioException catch (error) {
      if (await file.exists()) await file.delete();
      throw _fromNetwork(NetworkErrorNormalizer.fromDio(error));
    } catch (_) {
      if (await file.exists()) await file.delete();
      throw KlipyException(serviceLocalizations.stickerDownloadFailed);
    }
  }

  KlipyStickerPage _parseResponse(dynamic responseData) {
    final response = _asMap(responseData);
    final rawData = response?['results'];
    if (rawData is! List) {
      throw const FormatException('Missing Klipy results data.');
    }

    final stickers = <KlipySticker>[];
    for (final raw in rawData) {
      final item = _asMap(raw);
      final formats = _asMap(item?['media_formats']);
      final webp = _asMap(formats?['webp']);
      final url = webp?['url']?.toString().trim() ?? '';
      final dims = webp?['dims'];
      final uri = Uri.tryParse(url);
      if (item == null ||
          webp == null ||
          uri == null ||
          !(uri.scheme == 'https' || uri.scheme == 'http')) {
        continue;
      }
      final width = _dimAt(dims, 0);
      final height = _dimAt(dims, 1);
      stickers.add(
        KlipySticker(
          id: item['id']?.toString() ?? 'klipy_${stickers.length}',
          title:
              item['title']?.toString().trim().isNotEmpty == true
                  ? item['title'].toString().trim()
                  : serviceLocalizations.trendingSticker,
          url: url,
          width: width,
          height: height,
        ),
      );
    }

    final nextCursor = response?['next']?.toString().trim();
    return KlipyStickerPage(
      stickers: stickers,
      nextCursor: nextCursor?.isEmpty == true ? null : nextCursor,
    );
  }

  Future<KlipyStickerPage> _fetchPage({
    required String endpoint,
    required Map<String, dynamic> parameters,
    required String fallbackMessage,
    CancelToken? cancelToken,
  }) async {
    try {
      final customGet = apiGet;
      final response = customGet != null
          ? await customGet(endpoint, parameters)
          : await _networkClient.get<dynamic>(
              endpoint,
              queryParameters: parameters,
              options: Options(responseType: ResponseType.json),
              cancelToken: cancelToken,
            );
      return _parseResponse(response.data);
    } on KlipyException {
      rethrow;
    } on NetworkFailure catch (error) {
      throw _fromNetwork(error);
    } on DioException catch (error) {
      throw _fromNetwork(NetworkErrorNormalizer.fromDio(error));
    } on FormatException {
      throw KlipyException(serviceLocalizations.klipyUnreadableResponse);
    } on SocketException {
      throw KlipyException(serviceLocalizations.klipyConnectionFailed);
    } catch (_) {
      throw KlipyException(fallbackMessage);
    }
  }

  KlipyException _fromNetwork(NetworkFailure error) {
    final status = error.statusCode;
    if (error.kind == NetworkErrorKind.rateLimited) {
      return KlipyRateLimitException(error.message);
    }
    if (status == 401 || status == 403) {
      return KlipyException(serviceLocalizations.klipyRejectedApiKey);
    }
    return KlipyException(error.message);
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

int _dimAt(dynamic dims, int index) {
  if (dims is List && dims.length > index) {
    final v = dims[index];
    if (v is num) return v.toInt();
  }
  return 0;
}

final klipyServiceProvider = Provider<KlipyService>((ref) {
  final apiKeys = ref.watch(apiKeySettingsProvider);
  final key = apiKeys.klipyApiKey ?? '';
  return KlipyService(apiKey: key);
});
