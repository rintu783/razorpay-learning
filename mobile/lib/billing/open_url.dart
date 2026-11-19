import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Opens [url] in a new browser tab. The app is web only (see razorpay_web.dart).
void openInNewTab(String url) {
  globalContext.callMethod('open'.toJS, url.toJS, '_blank'.toJS);
}
