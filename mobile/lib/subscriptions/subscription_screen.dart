import 'package:flutter/material.dart';

import '../payments/payment_service.dart';
import '../payments/razorpay_web.dart';
import 'subscription_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _subs = SubscriptionService();
  final _payments = PaymentService();
  SubscriptionInfo? _info;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await _subs.me();
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = 'Cannot reach the server: $e');
    }
  }

  void _done(String msg) {
    setState(() {
      _busy = false;
      _message = msg;
    });
  }

  Future<void> _upgrade(Plan plan) async {
    setState(() {
      _busy = true;
      _message = 'Creating order...';
    });
    try {
      final order = await _subs.checkout(plan.id);
      setState(() => _message = 'Opening checkout...');
      openCheckout(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        onSuccess: (p) => _afterCheckout(order.orderId, p),
        onFailure: (m) => _done('Payment failed: $m'),
        onDismiss: () => _done('Checkout closed. You were not charged.'),
      );
    } catch (e) {
      _done('Error: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  // The app never upgrades itself. It waits until the backend (webhook) says Pro.
  Future<void> _afterCheckout(String orderId, PaymentSuccess p) async {
    setState(() => _message = 'Checking signature...');
    try {
      final ok = await _payments.verify(p.orderId, p.paymentId, p.signature);
      if (!ok) {
        _done('Signature invalid. Payment not trusted.');
        return;
      }
      for (var i = 0; i < 20; i++) {
        setState(() => _message = 'Payment received. Confirming with server... (${i + 1})');
        final info = await _subs.me();
        if (info.planId == 'pro') {
          setState(() => _info = info);
          _done('Welcome to Pro!');
          return;
        }
        if (await _payments.getStatus(orderId) == 'failed') {
          _done('Payment failed (confirmed by server).');
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      _done('Still confirming. Refresh in a moment.');
    } catch (e) {
      _done('Error: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _refund(SubscriptionInfo info) async {
    final orderId = info.refundableOrderId;
    if (orderId == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Pro plan?'),
        content: const Text(
            'Your full payment will be refunded and you will go back to the Basic plan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Pro')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Refund')),
        ],
      ),
    );
    if (sure != true) return;
    setState(() {
      _busy = true;
      _message = 'Requesting refund...';
    });
    try {
      await _subs.refund(orderId);
      // The app never downgrades itself. Wait for the refund webhook.
      for (var i = 0; i < 30; i++) {
        setState(() => _message = 'Refund in progress... waiting for confirmation (${i + 1})');
        final latest = await _subs.me();
        if (latest.planId == 'basic') {
          setState(() => _info = latest);
          _done('Refund processed. You are back on Basic.');
          return;
        }
        if (latest.refundStatus == 'failed') {
          setState(() => _info = latest);
          _done('Refund failed. You are still on Pro. Please try again.');
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      _done('Refund is still processing. Press refresh in a moment.');
    } catch (e) {
      _done('Error: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : info == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          children: [
                            _CurrentBanner(info: info),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final p in info.plans)
                                  _PlanCard(
                                    plan: p,
                                    current: p.id == info.planId,
                                    busy: _busy,
                                    onUpgrade: () => _upgrade(p),
                                    onRefund: p.id == info.planId &&
                                            info.refundableOrderId != null &&
                                            info.refundStatus != 'pending'
                                        ? () => _refund(info)
                                        : null,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (_busy) const LinearProgressIndicator(),
                            if (_message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(_message!, textAlign: TextAlign.center),
                              ),
                            const SizedBox(height: 12),
                            const Text('Test mode: no real money is charged.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CurrentBanner extends StatelessWidget {
  final SubscriptionInfo info;
  const _CurrentBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    final pro = info.planId == 'pro';
    final until = info.proUntil;
    final text = pro && info.refundStatus == 'pending'
        ? 'Refund in progress. You stay on Pro until it is confirmed.'
        : pro && until != null
            ? 'You are on Pro until ${until.day}/${until.month}/${until.year}'
            : 'You are on the Basic plan';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pro ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pro ? Colors.green : Colors.grey.shade400),
      ),
      child: Row(
        children: [
          Icon(pro ? Icons.workspace_premium : Icons.person_outline,
              color: pro ? Colors.green : Colors.grey),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool current;
  final bool busy;
  final VoidCallback onUpgrade;
  final VoidCallback? onRefund; // set only on the current, refundable plan
  const _PlanCard({
    required this.plan,
    required this.current,
    required this.busy,
    required this.onUpgrade,
    this.onRefund,
  });

  @override
  Widget build(BuildContext context) {
    final free = plan.priceRupees == 0;
    return SizedBox(
      width: 320,
      child: Card(
        elevation: current ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: current ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(plan.name, style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (current) const Chip(label: Text('Current')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                free ? 'Free' : 'Rs ${plan.priceRupees} / ${plan.days} days',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              for (final f in plan.features)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    const Icon(Icons.check, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f)),
                  ]),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: free || current
                    ? OutlinedButton(onPressed: null, child: Text(current ? 'Your plan' : 'Included'))
                    : FilledButton(
                        onPressed: busy ? null : onUpgrade,
                        child: Text('Upgrade to ${plan.name}'),
                      ),
              ),
              if (onRefund != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: busy ? null : onRefund,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Request refund'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
