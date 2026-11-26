import 'dart:convert';
import 'dart:typed_data';

import '../auth/api_client.dart';

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
  ApiClient get _api => ApiClient.instance;

  Future<List<HistoryItem>> history() async {
    final res = await _api.get('/billing/history');
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

  /// The PDF endpoint needs the Bearer token, which a plain link in a new tab cannot send. So the app
  /// downloads the bytes here and shows them from memory (see open_url.dart).
  Future<Uint8List> invoicePdf(String orderId) async {
    final res = await _api.get('/billing/invoices/$orderId/pdf');
    if (res.statusCode != 200) {
      throw ApiException(ApiClient.errorMessage(res, fallback: 'Could not load the invoice.'), res.statusCode);
    }
    return res.bodyBytes;
  }
}
