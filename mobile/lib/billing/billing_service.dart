import 'dart:convert';

import 'package:http/http.dart' as http;

import '../payments/payment_service.dart';

class HistoryItem {
  final String invoiceNo;
  final String orderId;
  final String planName;
  final double amountRupees;
  final DateTime paidAt;
  final DateTime validUntil;
  final String status; // paid | refunded
  HistoryItem(this.invoiceNo, this.orderId, this.planName, this.amountRupees,
      this.paidAt, this.validUntil, this.status);

  bool get refunded => status == 'refunded';
}

/// Talks to the backend /billing endpoints.
class BillingService {
  static const _base = PaymentService.baseUrl;

  Future<List<HistoryItem>> history() async {
    final res = await http.get(Uri.parse('$_base/billing/history'));
    if (res.statusCode != 200) {
      throw Exception('Could not load billing history (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['items'] as List)
        .map((i) => HistoryItem(
              i['invoice_no'],
              i['order_id'],
              i['plan_name'],
              (i['amount_rupees'] as num).toDouble(),
              DateTime.parse(i['paid_at']).toLocal(),
              DateTime.parse(i['valid_until']).toLocal(),
              i['status'],
            ))
        .toList();
  }

  /// The PDF is opened in a new tab, so the browser needs the full URL.
  String invoicePdfUrl(String orderId) => '$_base/billing/invoices/$orderId/pdf';
}
