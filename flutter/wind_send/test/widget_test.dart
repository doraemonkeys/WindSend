// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert/convert.dart';
import 'package:wind_send/main.dart';
import 'package:wind_send/device.dart';

void main() {
  var d = Device(
    targetDeviceName: 'test',
    iP: '127.0.0.1',
    secretKey: 'test',
  );
  test('test', () async {
    expect(d.refState().tryDirectConnectErr, isNull);
    d.refState().tryDirectConnectErr = Future.value(null);
    expect(d.refState().tryDirectConnectErr, isNotNull);
    d.refState().tryDirectConnectErr = Future.value("test");
    expect(d.refState().tryDirectConnectErr, isNotNull);
    final err = await d.refState().tryDirectConnectErr;
    expect(err, "test");
  });
}
