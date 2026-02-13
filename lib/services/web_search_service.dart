import 'dart:convert';

import 'package:http/http.dart' as http;

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    required this.source,
  });

  final String title;
  final String url;
  final String snippet;
  final String source;

  factory WebSearchResult.fromMap(Map<String, Object?> map) {
    return WebSearchResult(
      title: (map['title'] ?? '').toString().trim(),
      url: (map['url'] ?? '').toString().trim(),
      snippet: (map['snippet'] ?? '').toString().trim(),
      source: (map['source'] ?? '').toString().trim(),
    );
  }
}

class WebSearchService {
  const WebSearchService();

  Future<List<WebSearchResult>> search(String query, {int limit = 6}) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <WebSearchResult>[];
    }

    final clampedLimit = limit.clamp(1, 10);
    final uri = Uri.base.resolve(
      '/api/web-search?q=${Uri.encodeQueryComponent(normalizedQuery)}&limit=$clampedLimit',
    );

    try {
      final response = await http.get(
        uri,
        headers: const <String, String>{'Accept': 'application/json'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <WebSearchResult>[];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const <WebSearchResult>[];
      }
      final rows = decoded['results'];
      if (rows is! List) {
        return const <WebSearchResult>[];
      }
      return rows
          .whereType<Map>()
          .map(
            (row) => WebSearchResult.fromMap(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((row) => row.url.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <WebSearchResult>[];
    }
  }

  String buildContextBlock(List<WebSearchResult> results) {
    if (results.isEmpty) {
      return '';
    }
    final lines = <String>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      lines.add(
        '${i + 1}. ${result.title}\n'
        'URL: ${result.url}\n'
        'Фрагмент: ${result.snippet}\n'
        'Источник: ${result.source}',
      );
    }
    return lines.join('\n\n');
  }
}
