import 'dart:convert';

import '../auth/api_client.dart';
import '../payments/payment_service.dart';

class Plan {
  final String id;
  final String name;
  final int priceRupees;
  final int days;
  final List<String> features;
  Plan(this.id, this.name, this.priceRupees, this.days, this.features);
}

class SubscriptionInfo {
  final String planId;
  final DateTime? proUntil;
  final String? refundableOrderId;
  final String? refundStatus; // pending | processed | failed | null
  final List<Plan> plans;
  SubscriptionInfo(this.planId, this.proUntil, this.refundableOrderId,
      this.refundStatus, this.plans);
}

/// Talks to the backend /subscriptions endpoints. No keys here.
class SubscriptionService {
  ApiClient get _api => ApiClient.instance;

  Future<SubscriptionInfo> me() async {
    final res = await _api.get('/subscriptions/me');
    if (res.statusCode != 200) {
      throw Exception('Could not load subscription (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final plans = (j['plans'] as List)
        .map((p) => Plan(p['id'], p['name'], p['price_rupees'], p['days'],
            List<String>.from(p['features'])))
        .toList();
    final until = j['pro_until'] as String?;
    return SubscriptionInfo(
      j['plan_id'],
      until == null ? null : DateTime.parse(until).toLocal(),
      j['refundable_order_id'] as String?,
      j['refund_status'] as String?,
      plans,
    );
  }

  /// Sends only the plan name. The server decides the price.
  Future<OrderInfo> checkout(String planId) async {
    final res = await _api.post('/subscriptions/checkout', body: {'plan_id': planId});
    if (res.statusCode != 200) {
      final detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      throw Exception('$detail');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return OrderInfo(j['order_id'], j['amount'], j['key_id']);
  }

  /// Starts a full refund. The server's webhook later moves the user to Basic.
  Future<void> refund(String orderId) async {
    final res = await _api.post('/payments/$orderId/refund');
    if (res.statusCode != 200) {
      final detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      throw Exception('$detail');
    }
  }
}
