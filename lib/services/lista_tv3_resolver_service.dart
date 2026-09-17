import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'lista_tv3_metadata_registry.dart';
import 'remote_provisioning_service.dart';

class ListaTv3ResolverException implements Exception {
  final String message;
  final bool retryable;

  const ListaTv3ResolverException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

class ListaTv3ResolvedStream {
  final String url;
  final Map<String, String> headers;

  const ListaTv3ResolvedStream({required this.url, required this.headers});
}

class ListaTv3ResolverService {
  ListaTv3ResolverService._({http.Client? client})
    : _client = client ?? http.Client();

  static final ListaTv3ResolverService instance = ListaTv3ResolverService._();

  static const String _endpoint =
      'https://ghsoudpjlnjmhiragkrm.supabase.co/functions/v1/tvf-lista3-resolve';

  final http.Client _client;

  bool handles(Channel channel) =>
      channel.group == 'Lista TV 3' &&
      (channel.dynamicStreamId?.trim().isNotEmpty ?? false);

  Future<ListaTv3ResolvedStream> resolve(Channel channel) async {
    final channelCode = channel.dynamicStreamId?.trim() ?? '';
    if (channelCode.isEmpty) {
      throw const ListaTv3ResolverException('El canal no tiene channelCode.');
    }

    final metadata = ListaTv3MetadataRegistry.instance.channel(channelCode);
    final variants = metadata?.variants ?? const <ListaTv3StreamVariant>[];
    if (variants.isEmpty) {
      throw const ListaTv3ResolverException(
        'El canal no contiene variantes de reproducción.',
      );
    }

    final credentials = await RemoteProvisioningService().ensureRegistered();
    Object? lastError;

    for (final variant in variants) {
      try {
        final response = await _client
            .post(
              Uri.parse(_endpoint),
              headers: <String, String>{
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'x-tvfull-device-code': credentials.code,
                'x-tvfull-device-secret': credentials.secret,
              },
              body: jsonEncode(<String, dynamic>{
                'channelCode': channelCode,
                'name': channel.name,
                'playCode': variant.playCode,
                if (variant.mediaCode != null) 'mediaCode': variant.mediaCode,
                if (variant.cdnType != null) 'cdnType': variant.cdnType,
                if (variant.tag != null) 'tag': variant.tag,
                if (variant.quality != null) 'quality': variant.quality,
                if (variant.avFormat != null) 'avFormat': variant.avFormat,
              }),
            )
            .timeout(const Duration(seconds: 18));

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const ListaTv3ResolverException(
            'El dispositivo no está autorizado para resolver Lista TV 3.',
          );
        }
        if (response.statusCode == 404) {
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }

        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (decoded is! Map) continue;
        final data = Map<String, dynamic>.from(decoded);
        final rawUrl = data['url']?.toString().trim() ?? '';
        final uri = Uri.tryParse(rawUrl);
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          continue;
        }

        final headers = <String, String>{};
        final rawHeaders = data['headers'];
        if (rawHeaders is Map) {
          for (final entry in rawHeaders.entries) {
            final key = entry.key?.toString().trim() ?? '';
            final value = entry.value?.toString().trim() ?? '';
            if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;
          }
        }
        return ListaTv3ResolvedStream(url: uri.toString(), headers: headers);
      } on ListaTv3ResolverException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }

    throw ListaTv3ResolverException(
      lastError == null
          ? 'No se encontró una señal autorizada para este canal.'
          : 'No se pudo resolver una señal autorizada para este canal.',
      retryable: true,
    );
  }
}
