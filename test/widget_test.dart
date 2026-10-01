import 'package:buildify_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('app starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BuildifyApp()));
    await tester.pump();
    // The ProviderScope wrapping a MaterialApp must be present.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
