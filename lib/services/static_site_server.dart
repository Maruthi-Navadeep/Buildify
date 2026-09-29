import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

class StaticSiteServer {
  HttpServer? _server;
  final String localPath;
  final int port;
  final String publishDir; // relative path within localPath
  final void Function(String message, {bool isError})? onLog;

  StaticSiteServer({
    required this.localPath,
    required this.port,
    this.publishDir = '',
    this.onLog,
  });

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    // Bind to loopback only. The project is exposed publicly through the
    // Cloudflare tunnel (cloudflared connects locally), so there is no reason
    // to listen on all interfaces and expose the dev server to the LAN.
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
    onLog?.call('[server] listening on 127.0.0.1:$port serving $localPath');
    
    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  File? _findFile(String rootPath, String relativePath) {
    final normalizedRoot = p.normalize(p.absolute(rootPath));

    // Reject any candidate that escapes the project root (path traversal).
    bool isContained(String candidate) {
      final n = p.normalize(p.absolute(candidate));
      return p.equals(n, normalizedRoot) || p.isWithin(normalizedRoot, n);
    }

    // 1. Direct match in rootDir
    final directPath = p.normalize(p.join(rootPath, relativePath));
    if (isContained(directPath)) {
      final candidate = File(directPath);
      if (candidate.existsSync()) return candidate;
    }

    // 2. Check if files were extracted into a single subfolder
    final rootDir = Directory(rootPath);
    if (rootDir.existsSync()) {
      for (final entity in rootDir.listSync()) {
        if (entity is Directory) {
          final nestedPath = p.normalize(p.join(entity.path, relativePath));
          if (isContained(nestedPath)) {
            final nested = File(nestedPath);
            if (nested.existsSync()) return nested;
          }
        }
      }
    }
    return null;
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  void _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      String reqPath = request.uri.path;
      if (reqPath == '/' || reqPath.isEmpty) {
        reqPath = '/index.html';
      }

      final relPath = reqPath.startsWith('/') ? reqPath.substring(1) : reqPath;
      final rootDir = p.join(localPath, publishDir);

      File? targetFile = _findFile(rootDir, relPath);

      // Fallback for root index.html or SPA routing
      if (targetFile == null || !targetFile.existsSync()) {
        targetFile = _findFile(rootDir, 'index.html');
      }

      if (targetFile != null && await targetFile.exists()) {
        onLog?.call('[server] 200 GET $reqPath -> ${targetFile.path}');
        final mimeType = lookupMimeType(targetFile.path) ?? 'text/html';
        response.headers.contentType = ContentType.parse(mimeType);
        
        await targetFile.openRead().pipe(response);
      } else {
        onLog?.call('[server] 404 GET $reqPath (not found in $rootDir)', isError: true);
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType = ContentType.html;
        response.write('<html><body><h1>404 Not Found</h1><p>No file matching <code>${_escapeHtml(reqPath)}</code> found in project directory.</p></body></html>');
        await response.close();
      }
    } catch (e) {
      onLog?.call('[server] Error handling request: $e', isError: true);
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.html;
        response.write('<html><body><h1>500 Internal Server Error</h1></body></html>');
        await response.close();
      } catch (_) {}
    }
  }
}
