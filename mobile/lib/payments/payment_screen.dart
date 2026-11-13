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

  // Steps 7-9: send the 3 values to the backend; ONLY the backend says paid.
  Future<void> _onSuccess(PaymentSuccess p) async {
    setState(() => _status = 'Verifying with server...');
    try {
      final ok = await _service.verify(p.orderId, p.paymentId, p.signature);
      setState(() {
        _busy = false;
        _status = ok
            ? 'PAID and verified\npayment: ${p.paymentId}'
            : 'Verification FAILED - do not trust this payment';
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
