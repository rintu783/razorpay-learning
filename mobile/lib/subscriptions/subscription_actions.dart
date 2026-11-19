import 'package:flutter/material.dart';

import '../payments/payment_service.dart';
import '../payments/razorpay_web.dart';
import 'subscription_service.dart';

/// Shared upgrade and refund logic for screens that show subscription state.
///
/// The app never changes the plan itself. After checkout or refund it polls
/// the backend until the webhook has moved the plan.
mixin SubscriptionActions<T extends StatefulWidget> on State<T> {
  final subs = SubscriptionService();
  final _payments = PaymentService();

  SubscriptionInfo? info;
  bool busy = false;
  String? message;
  String? loadError;

  Future<void> loadInfo() async {
    try {
      final latest = await subs.me();
      if (mounted) {
        setState(() {
          info = latest;
          loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadError = 'Cannot reach the server: $e');
    }
  }

  /// Called when an upgrade or refund finishes. Screens override it to reload extra data.
  void onActionDone() {}

  void _done(String msg) {
    if (!mounted) return;
    setState(() {
      busy = false;
      message = msg;
    });
    onActionDone();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> upgrade(Plan plan) async {
    setState(() {
      busy = true;
      message = 'Creating order...';
    });
    try {
      final order = await subs.checkout(plan.id);
      if (mounted) setState(() => message = 'Opening checkout...');
      openCheckout(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        onSuccess: (p) => _afterCheckout(order.orderId, p),
        onFailure: (m) => _done('Payment failed: $m'),
        onDismiss: () => _done('Checkout closed. You were not charged.'),
      );
    } catch (e) {
      _done('Error: ${_clean(e)}');
    }
  }

  Future<void> _afterCheckout(String orderId, PaymentSuccess p) async {
    if (mounted) setState(() => message = 'Checking signature...');
    try {
      final ok = await _payments.verify(p.orderId, p.paymentId, p.signature);
      if (!ok) {
        _done('Signature invalid. Payment not trusted.');
        return;
      }
      for (var i = 0; i < 20 && mounted; i++) {
        setState(() => message = 'Payment received. Confirming with server... (${i + 1})');
        final latest = await subs.me();
        if (latest.planId == 'pro') {
          if (mounted) setState(() => info = latest);
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
      _done('Error: ${_clean(e)}');
    }
  }

  /// Cancel = full refund through the existing refund flow.
  Future<void> cancelAndRefund() async {
    final orderId = info?.refundableOrderId;
    if (orderId == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Pro plan?'),
        content: const Text(
            'Your full payment will be refunded and you will go back to the Basic plan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Pro')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel and refund')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      busy = true;
      message = 'Requesting refund...';
    });
    try {
      await subs.refund(orderId);
      for (var i = 0; i < 30 && mounted; i++) {
        setState(() => message = 'Refund in progress... waiting for confirmation (${i + 1})');
        final latest = await subs.me();
        if (latest.planId == 'basic') {
          if (mounted) setState(() => info = latest);
          _done('Refund processed. You are back on Basic.');
          return;
        }
        if (latest.refundStatus == 'failed') {
          if (mounted) setState(() => info = latest);
          _done('Refund failed. You are still on Pro. Please try again.');
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      _done('Refund is still processing. Press refresh in a moment.');
    } catch (e) {
      _done('Error: ${_clean(e)}');
    }
  }
}
