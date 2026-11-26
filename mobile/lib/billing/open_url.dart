import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Shows a PDF in a new browser tab. The app is web only (see razorpay_web.dart).
///
/// The tab is opened first, while the click is still being handled, because browsers block
/// pop-ups that are opened after an `await`. The PDF bytes then arrive and are shown from an
/// in-memory blob, so the Bearer token never appears in a URL.
Future<void> openPdfInNewTab(Future<Uint8List> pdf) async {
  final tab = web.window.open('', '_blank');
  try {
    final bytes = await pdf;
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
    final url = web.URL.createObjectURL(blob);
    tab?.location.href = url;
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url)); // free the memory later
  } catch (_) {
    tab?.close();
    rethrow;
  }
}
