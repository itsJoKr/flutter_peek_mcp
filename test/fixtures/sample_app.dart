// A small app that produces console output and HTTP traffic for
// vm_client_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(_serve);
  final base = 'http://127.0.0.1:${server.port}';
  final client = HttpClient();

  var tick = 0;
  Timer.periodic(const Duration(milliseconds: 300), (_) async {
    tick++;
    print('duplicate line');
    print('duplicate line');
    try {
      throw StateError('boom $tick');
    } catch (e, st) {
      log('tick $tick failed',
          name: 'sample', level: 1000, error: e, stackTrace: st);
    }

    final request = await client.postUrl(Uri.parse('$base/orders'));
    request.headers.set('authorization', 'Bearer secret-token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'orderId': 'ORD-$tick'}));
    await (await request.close()).drain<void>();

    final image = await client.getUrl(Uri.parse('$base/logo.png'));
    await (await image.close()).drain<void>();
  });
}

Future<void> _serve(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  final response = request.response;
  if (request.uri.path == '/logo.png') {
    response.headers.contentType = ContentType('image', 'png');
    response.add([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE, 0x00, 0x01]);
  } else {
    response.statusCode = HttpStatus.created;
    response.headers.contentType = ContentType.json;
    response.write(body);
  }
  await response.close();
}
