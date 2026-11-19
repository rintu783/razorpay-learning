import 'package:flutter/material.dart';

import 'billing_service.dart';

/// Billing history rows. Columns share the available width, so the print
/// button always stays inside the card.
class HistoryTable extends StatelessWidget {
  final List<HistoryItem> items;
  final String Function(DateTime) formatDate;
  final void Function(HistoryItem) onPrint;
  const HistoryTable({
    super.key,
    required this.items,
    required this.formatDate,
    required this.onPrint,
  });

  static const _head = TextStyle(fontWeight: FontWeight.w600, fontSize: 13);
  static const _cell = TextStyle(fontSize: 13);

  Widget _t(String text, TextStyle style, {TextAlign align = TextAlign.start}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(text, style: style, textAlign: align, maxLines: 2, overflow: TextOverflow.ellipsis),
      );

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: Colors.grey.shade300);
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(2.2), // Date paid
        1: FlexColumnWidth(1.0), // Plan
        2: FlexColumnWidth(1.8), // Amount
        3: FlexColumnWidth(2.2), // Valid till
        4: FlexColumnWidth(1.6), // Status
        5: FixedColumnWidth(48), // Invoice
      },
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: line)),
          children: [
            _t('Date paid', _head),
            _t('Plan', _head),
            _t('Amount', _head),
            _t('Valid till', _head),
            _t('Status', _head),
            const SizedBox.shrink(),
          ],
        ),
        for (final h in items)
          TableRow(
            decoration: BoxDecoration(border: Border(bottom: line)),
            children: [
              _t(formatDate(h.paidAt), _cell),
              _t(h.planName, _cell),
              _t('Rs ${h.amountRupees.toStringAsFixed(2)}', _cell),
              _t(formatDate(h.validUntil), _cell),
              _t(
                h.refunded ? 'Refunded' : 'Paid',
                _cell.copyWith(
                  fontWeight: FontWeight.w600,
                  color: h.refunded ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
              IconButton(
                tooltip: 'Print invoice ${h.invoiceNo}',
                icon: const Icon(Icons.print_outlined),
                onPressed: () => onPrint(h),
              ),
            ],
          ),
      ],
    );
  }
}
