import 'package:flutter/material.dart';

import '../subscriptions/subscription_actions.dart';
import 'billing_service.dart';
import 'history_table.dart';
import 'open_url.dart';
import '../subscriptions/subscription_service.dart';

/// Billing page: plan status, price, days meter, and the Upgrade and Cancel buttons.
/// Upgrade opens the Razorpay popup. Cancel refunds through the existing refund flow.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> with SubscriptionActions<BillingScreen> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final _billing = BillingService();

  Future<void> _openInvoice(String orderId) async {
    try {
      await openPdfInNewTab(_billing.invoicePdf(orderId));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the invoice. Please try again.')));
    }
  }
  List<HistoryItem>? _history;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    loadInfo();
    _loadHistory();
  }

  @override
  void onActionDone() => _loadHistory();

  Future<void> _loadHistory() async {
    try {
      final items = await _billing.history();
      if (mounted) {
        setState(() {
          _history = items;
          _historyError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _historyError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

  Plan _proPlan(SubscriptionInfo i) => i.plans.firstWhere((p) => p.id == 'pro');

  @override
  Widget build(BuildContext context) {
    final i = info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy
                ? null
                : () {
                    loadInfo();
                    _loadHistory();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loadError != null && i == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loadError!),
                  TextButton(onPressed: loadInfo, child: const Text('Retry')),
                ],
              ),
            )
          : i == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          children: [
                            _content(context, i),
                            const SizedBox(height: 16),
                            _historyCard(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _content(BuildContext context, SubscriptionInfo i) {
    final pro = i.planId == 'pro';
    final plan = _proPlan(i);
    final until = i.proUntil;
    final grey = TextStyle(color: Colors.grey.shade600);
    const bold = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    final refundPending = pro && i.refundStatus == 'pending';
    final canCancel = pro && i.refundableOrderId != null && !refundPending && !busy;
    final canUpgrade = !pro && !busy;

    // Days meter, only while Pro is active.
    double? usedFraction;
    String? meterCaption;
    if (pro && until != null) {
      final remaining = until.difference(DateTime.now()).inHours / 24;
      final remainingDays = remaining.ceil().clamp(0, plan.days);
      usedFraction = ((plan.days - remainingDays) / plan.days).clamp(0.0, 1.0);
      meterCaption = '$remainingDays days remaining until your plan expires';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (usedFraction != null) ...[
              Row(
                children: [
                  const Text('Plan days', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${(usedFraction * plan.days).round()} / ${plan.days}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: usedFraction, minHeight: 6),
              ),
              const SizedBox(height: 8),
              Text(meterCaption!, style: grey),
              const SizedBox(height: 24),
            ],
            Text(pro && until != null ? 'Active until ${_date(until)}' : 'Basic plan, no expiry',
                style: bold),
            const SizedBox(height: 4),
            Text(
              pro
                  ? (refundPending
                      ? 'Refund in progress. You stay on Pro until it is confirmed.'
                      : 'Your plan ends on this date.')
                  : 'Upgrade to Pro any time.',
              style: grey,
            ),
            const SizedBox(height: 24),
            Text('Rs ${plan.priceRupees} / ${plan.days} days', style: bold),
            const SizedBox(height: 4),
            Text('${plan.name} plan. ${plan.features.join('. ')}', style: grey),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: canUpgrade ? () => upgrade(plan) : null,
                  child: const Text('Upgrade Plan'),
                ),
                OutlinedButton(
                  onPressed: canCancel ? cancelAndRefund : null,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: LinearProgressIndicator(),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(message!),
              ),
            const SizedBox(height: 16),
            Text('Test mode: no real money is charged.', style: grey),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(BuildContext context) {
    final grey = TextStyle(color: Colors.grey.shade600);
    final items = _history;
    Widget body;
    if (_historyError != null && items == null) {
      body = Row(children: [
        Expanded(child: Text(_historyError!, style: grey)),
        TextButton(onPressed: _loadHistory, child: const Text('Retry')),
      ]);
    } else if (items == null) {
      body = const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    } else if (items.isEmpty) {
      body = Text('No payments yet.', style: grey);
    } else {
      body = HistoryTable(
        items: items,
        formatDate: _date,
        onPrint: (h) => _openInvoice(h.orderId),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Billing history',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            body,
          ],
        ),
      ),
    );
  }
}
