import 'dart:convert';

import '../auth/api_client.dart';

class OrderInfo {
  final String orderId;
  final int amountPaise;
  final String keyId;
  OrderInfo(this.orderId, this.amountPaise, this.keyId);
}

/// Talks to OUR backend only. Never holds the Key Secret.
class PaymentService {
  static const baseUrl = ApiClient.defaultBaseUrl;

  ApiClient get _api => ApiClient.instance;

  Future<OrderInfo> createOrder(double amountRupees) async {
    final res = await _api.post('/payments/create-order', body: {'amount': amountRupees});
    if (res.statusCode != 200) {
      throw Exception('Create order failed (${res.statusCode}): ${res.body}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return OrderInfo(j['order_id'], j['amount'], j['key_id']);
  }

  /// Returns true only if the backend verified the signature.
  Future<bool> verify(String orderId, String paymentId, String signature) async {
    final res = await _api.post('/payments/verify', body: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    if (res.statusCode != 200) {
      throw Exception('Verify failed (${res.statusCode}): ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['verified'] == true;
  }

  /// Status as saved by the backend (updated only by the Razorpay webhook).
  /// Returns "created", "paid" or "failed".
  Future<String> getStatus(String orderId) async {
    final res = await _api.get('/payments/status/$orderId');
    if (res.statusCode != 200) {
      throw Exception('Status failed (${res.statusCode}): ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['status'] as String;
  }
}
