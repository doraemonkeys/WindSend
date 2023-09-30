import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

import 'package:flutter/services.dart';
import 'package:wind_send/aes_lib2/aes_crypt_null_safe.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

class WebSync {
  static const baseWebUrl = "https://ko0.com";
  static const submitUrl = "https://ko0.com/submit/";
  static const userAgent =
      "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/534.16 (KHTML, like Gecko) Chrome/10.0.648.133 Safari/534.16";
  final String secretKeyHex;
  late String myUrl;
  late Dio dioClient;

  WebSync(this.secretKeyHex) {
    var rkey = getSha256(utf8.encode(secretKeyHex));
    rkey = getSha256(rkey);
    var rkeyHashHex = hex.encode(rkey);
    myUrl = '$baseWebUrl/${rkeyHashHex.substring(0, 16)}';
    //print('myUrl: $myUrl');
    final dio = Dio();
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    dioClient = dio;
  }

  Future<Uint8List> getContentFromWeb() async {
    // var client = http.Client();
    // var request = http.Request('GET', Uri.parse(myUrl));
    // request.headers['User-Agent'] = userAgent;
    // var response = await client.send(request);
    // var body = await response.stream.toBytes();
    var headers = {
      'User-Agent': userAgent,
    };
    var response =
        await dioClient.get(myUrl, options: Options(headers: headers));
    var body = response.data;

    // class[\s]*=[\s]*"txt_view">[\s]*<p>(.+)<\/p>
    var re = RegExp(r'class[\s]*=[\s]*"txt_view">[\s]*<p>(.+)<\/p>');
    var match = re.firstMatch(body);
    if (match == null) {
      throw Exception('can not find content');
    }
    var content = match.group(1)!;
    // hex decode
    var encryptedata = hex.decode(content);
    var encryptedataUint8List = Uint8List.fromList(encryptedata);
    // decrypt
    var cryptor = CbcAESCrypt.fromHex(secretKeyHex);
    var decrypted = cryptor.decrypt(encryptedataUint8List);
    return decrypted;
  }

  Future<String> _getCsrfmiddlewaretoken(String myUrl, String userAgent) async {
    var headers = {
      'User-Agent': userAgent,
    };
    var response =
        await dioClient.get(myUrl, options: Options(headers: headers));
    return parseCsrfmiddlewaretoken(response.data);
  }

  String parseCsrfmiddlewaretoken(String content) {
    var re = RegExp(r'name="csrfmiddlewaretoken" value="(.+)">');
    var match = re.firstMatch(content);
    if (match == null) {
      throw Exception('can not find csrfmiddlewaretoken');
    }
    return match.group(1)!;
  }

  Future<void> postContentToWeb(String content) async {
    String csrfmiddlewaretoken =
        await _getCsrfmiddlewaretoken(myUrl, userAgent);
    var crypter = CbcAESCrypt.fromHex(secretKeyHex);
    var contentList = utf8.encode(content);
    var encryptedata = crypter.encrypt(Uint8List.fromList(contentList));
    var encryptedataHex = hex.encode(encryptedata);

    var payload = FormData.fromMap({
      'csrfmiddlewaretoken': csrfmiddlewaretoken,
      'txt': encryptedataHex,
      'code': myUrl.substring(myUrl.lastIndexOf('/') + 1),
      'sub_type': 'T',
      'file': '',
    });
    // header
    var headers = {
      'Referer': myUrl,
      'User-Agent': userAgent,
      'Content-Type': payload.boundary,
    };
    // print("content-type: ${payload.boundary}");
    // post
    var response = await dioClient.post(submitUrl,
        data: payload, options: Options(headers: headers));
    if (!response.data.contains('success')) {
      throw Exception('post content failed');
    }
  }
}

List<int> getSha256(List<int> input) {
  // var bytes = Uint8List.fromList(input);
  var digest = sha256.convert(input);
  return digest.bytes;
}
