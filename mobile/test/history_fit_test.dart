import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:razorpay_demo/billing/billing_service.dart';
import 'package:razorpay_demo/billing/history_table.dart';

void main() {
  final items = [
    HistoryItem('WHK-2026-0008', 'order_1', 'Pro', 499, DateTime(2026, 11, 19), DateTime(2026, 12, 19), 'paid'),
    HistoryItem('WHK-2026-0007', 'order_2', 'Pro', 499, DateTime(2026, 11, 19), DateTime(2026, 12, 19), 'refunded'),
  ];

  for (final width in [340.0, 592.0, 712.0]) {
    testWidgets('print icon stays inside a $width px card', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: HistoryTable(items: items, formatDate: (d) => '19 Nov 2026', onPrint: (_) {}),
            ),
          ),
        ),
      ));
      final icons = find.byIcon(Icons.print_outlined);
      expect(icons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(tester.getTopRight(icons.at(i)).dx, lessThanOrEqualTo(width));
        expect(tester.getTopLeft(icons.at(i)).dx, greaterThanOrEqualTo(0));
      }
    });
  }
}
