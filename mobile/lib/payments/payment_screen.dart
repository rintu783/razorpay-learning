import 'package:flutter/material.dart';

import 'payment_service.dart';
import 'razorpay_web.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _service = PaymentService();
  final _amountCtrl = TextEditingController(text: '500');
  bool _busy = false;
  String _status = 'Ready';

  Future<void> _pay() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _status = 'Enter a valid amount');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Creating order...';
    });
    try {
      // Steps 2-4 of the flow: backend creates the order.
      final order = await _service.createOrder(amount);
      setState(() => _status = 'Opening checkout...');
      // Step 5: open Razorpay checkout (public Key ID only).
      openCheckout(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        onSuccess: _onSuccess,
        onFailure: (m) => setState(() {
          _busy = false;
          _status = 'Payment failed: $m';
        }),
        onDismiss: () => setState(() {
          _busy = false;
          _status = 'Checkout closed (not paid)';
        }),
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  // After checkout: pre-check the signature, then wait for the WEBHOOK to
  // mark the order paid. The app never decides "paid" itself.
  Future<void> _onSuccess(PaymentSuccess p) async {
    setState(() => _status = 'Checking signature...');
    try {
      final ok = await _service.verify(p.orderId, p.paymentId, p.signature);
      if (!ok) {
        setState(() {
          _busy = false;
          _status = 'Signature invalid - do not trust this payment';
        });
        return;
      }
      // Poll our backend until the webhook has updated the status (max ~40s).
      for (var i = 0; i < 20; i++) {
        setState(() => _status = 'Waiting for payment confirmation... (${i + 1})');
        final status = await _service.getStatus(p.orderId);
        if (status == 'paid') {
          setState(() {
            _busy = false;
            _status = 'PAID (confirmed by webhook)\npayment: ${p.paymentId}';
          });
          return;
        }
        if (status == 'failed') {
          setState(() {
            _busy = false;
            _status = 'Payment FAILED (confirmed by webhook)';
          });
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      setState(() {
        _busy = false;
        _status = 'Still pending. Check again later (order ${p.orderId})';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Error: $e';
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Razorpay Demo (Test Mode)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _pay,
                child: const Text('Pay'),
              ),
              const SizedBox(height: 24),
              Text(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
