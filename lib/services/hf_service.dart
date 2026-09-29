import 'dart:convert';
import 'package:http/http.dart' as http;

class HfModelFile {
  const HfModelFile({
    required this.rfilename,
    required this.size,
  });

  final String rfilename; // e.g. "mistral-7b-instruct-v0.2.Q4_K_M.gguf"
  final int size; // bytes, 0 if unknown

  String get quantLabel {
    final upper = rfilename.toUpperCase();
    final match = RegExp(r'Q\d[A-Z0-9_]*').firstMatch(upper);
    return match?.group(0) ?? '';
  }

  String get sizeLabel {
    if (size <= 0) return '?';
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(size / (1024 * 1024)).round()} MB';
  }

  String downloadUrl(String repoId) =>
      'https://huggingface.co/$repoId/resolve/main/$rfilename';
}

class HfSearchResult {
  const HfSearchResult({
    required this.id,
    required this.displayName,
    required this.downloads,
    required this.likes,
    required this.ggufFileCount,
  });

  final String id; // e.g. "TheBloke/Mistral-7B-Instruct-v0.2-GGUF"
  final String displayName; // e.g. "Mistral-7B-Instruct-v0.2-GGUF"
  final int downloads;
  final int likes;
  final int ggufFileCount;

  factory HfSearchResult.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final displayName = json['modelId'] as String? ?? id.split('/').last;
    final downloads = (json['downloads'] as num?)?.toInt() ?? 0;
    final likes = (json['likes'] as num?)?.toInt() ?? 0;
    final siblings = json['siblings'] as List<dynamic>? ?? [];
    final ggufCount = siblings
        .whereType<Map<String, dynamic>>()
        .where((s) =>
            (s['rfilename'] as String? ?? '').toLowerCase().endsWith('.gguf'))
        .length;
    return HfSearchResult(
      id: id,
      displayName: displayName,
      downloads: downloads,
      likes: likes,
      ggufFileCount: ggufCount,
    );
  }
}

class HfService {
  static const _api = 'https://huggingface.co/api';
  static final _client = http.Client();

  static Future<List<HfSearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$_api/models').replace(queryParameters: {
      'search': query.trim(),
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '20',
    });
    try {
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(HfSearchResult.fromJson)
          .where((r) => r.ggufFileCount > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<HfModelFile>> getModelFiles(String repoId) async {
    try {
      final resp = await _client
          .get(Uri.parse('$_api/models/$repoId'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final siblings = json['siblings'] as List<dynamic>? ?? [];
      final files = siblings
          .whereType<Map<String, dynamic>>()
          .where((s) =>
              (s['rfilename'] as String? ?? '').toLowerCase().endsWith('.gguf'))
          .map((s) => HfModelFile(
                rfilename: s['rfilename'] as String,
                size: (s['size'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      // Sort: smaller quant first, then by size
      files.sort((a, b) => a.size.compareTo(b.size));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// Parses an HF URL.
  /// Returns (repoId, filename?) or null if not an HF URL.
  static ({String repoId, String? filename})? parseHfUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (!uri.host.contains('huggingface.co')) return null;
      final segs =
          uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length < 2) return null;
      final repoId = '${segs[0]}/${segs[1]}';
      if (segs.length >= 4 && segs[2] == 'resolve') {
        return (repoId: repoId, filename: segs.sublist(3).join('/'));
      }
      return (repoId: repoId, filename: null);
    } catch (_) {
      return null;
    }
  }

  static bool isDirectGgufUrl(String url) {
    try {
      return Uri.parse(url.trim())
          .pathSegments
          .last
          .toLowerCase()
          .endsWith('.gguf');
    } catch (_) {
      return false;
    }
  }
}
