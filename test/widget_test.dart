// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:air_money/presentation/pages/home/home_page.dart';
import 'package:air_money/presentation/providers/bill_provider.dart';
import 'package:air_money/presentation/providers/points_provider.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BillProvider()),
          ChangeNotifierProvider(create: (_) => PointsProvider()),
        ],
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );
    expect(find.text('哎呀钱'), findsOneWidget);
  });
}
