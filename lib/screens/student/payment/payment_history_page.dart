import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock Data for History
    final List<Map<String, dynamic>> history = [
      {'title': 'Tuition Fee - September', 'date': DateTime(2023, 9, 25), 'amount': 150.00, 'status': 'Paid'},
      {'title': 'Science Material Fee', 'date': DateTime(2023, 9, 10), 'amount': 50.00, 'status': 'Paid'},
      {'title': 'Tuition Fee - August', 'date': DateTime(2023, 8, 25), 'amount': 150.00, 'status': 'Paid'},
      {'title': 'Extra Class - Math', 'date': DateTime(2023, 8, 15), 'amount': 30.00, 'status': 'Paid'},
      {'title': 'Tuition Fee - July', 'date': DateTime(2023, 7, 25), 'amount': 150.00, 'status': 'Paid'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Transaction History"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        separatorBuilder: (c, i) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = history[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt, color: Color(0xff1458a3), size: 24),
              ),
              title: Text(
                item['title'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(item['date']),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        item['status'].toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Text(
                "RM ${item['amount'].toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              onTap: () {
                // Show details dialog
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Transaction Details"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow("Item:", item['title']),
                        _detailRow("Date:", DateFormat('dd MMM yyyy, h:mm a').format(item['date'])),
                        _detailRow("Amount:", "RM ${item['amount'].toStringAsFixed(2)}"),
                        _detailRow("Status:", item['status']),
                        _detailRow("Transaction ID:", "TXN-${10000 + index}"),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1458a3)),
                        child: const Text("Download Receipt", style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}