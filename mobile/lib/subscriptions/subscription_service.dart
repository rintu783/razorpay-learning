import 'dart:convert';

import 'package:http/http.dart' as http;

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
  final List<Plan> plans;
  SubscriptionInfo(this.planId, this.proUntil, this.plans);
}

/// Talks to the backend /subscriptions endpoints. No keys here.
class SubscriptionService {
  static const _base = PaymentService.baseUrl;

  Future<SubscriptionInfo> me() async {
    final res = await http.get(Uri.parse('$_base/subscriptions/me'));
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
      plans,
    );
  }

  /// Sends only the plan name. The server decides the price.
  Future<OrderInfo> checkout(String planId) async {
    final res = await http.post(
      Uri.parse('$_base/subscriptions/checkout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'plan_id': planId}),
    );
    if (res.statusCode != 200) {
      final detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      throw Exception('$detail');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return OrderInfo(j['order_id'], j['amount'], j['key_id']);
  }
}
