import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Thin wrapper over Razorpay's checkout.js (loaded in web/index.html).
@JS('Razorpay')
extension type _RazorpayJs._(JSObject _) implements JSObject {
  external _RazorpayJs(JSObject options);
  external void open();
  external void on(String event, JSFunction handler);
}

class PaymentSuccess {
  final String orderId;
  final String paymentId;
  final String signature;
  PaymentSuccess(this.orderId, this.paymentId, this.signature);
}

/// Opens the checkout popup. Only the public Key ID is used here.
void openCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required void Function(PaymentSuccess) onSuccess,
  required void Function(String message) onFailure,
  required void Function() onDismiss,
}) {
  String read(JSObject o, String k) =>
      (o.getProperty<JSAny?>(k.toJS) as JSString?)?.toDart ?? '';

  final options = JSObject()
    ..setProperty('key'.toJS, keyId.toJS)
    ..setProperty('order_id'.toJS, orderId.toJS)
    ..setProperty('amount'.toJS, amountPaise.toJS)
    ..setProperty('currency'.toJS, 'INR'.toJS)
    ..setProperty('name'.toJS, 'Razorpay Learning Demo'.toJS)
    ..setProperty('description'.toJS, 'Test payment'.toJS)
    ..setProperty(
      'handler'.toJS,
      ((JSObject r) {
        onSuccess(PaymentSuccess(
          read(r, 'razorpay_order_id'),
          read(r, 'razorpay_payment_id'),
          read(r, 'razorpay_signature'),
        ));
      }).toJS,
    );

  final modal = JSObject()
    ..setProperty('ondismiss'.toJS, (() => onDismiss()).toJS);
  options.setProperty('modal'.toJS, modal);

  final rzp = _RazorpayJs(options);
  rzp.on(
    'payment.failed',
    ((JSObject resp) {
      final err = resp.getProperty<JSAny?>('error'.toJS);
      final msg = err == null
          ? 'Payment failed'
          : read(err as JSObject, 'description');
      onFailure(msg.isEmpty ? 'Payment failed' : msg);
    }).toJS,
  );
  rzp.open();
}
