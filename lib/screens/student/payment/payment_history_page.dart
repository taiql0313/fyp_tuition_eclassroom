import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final paymentService = PaymentService();
    final auth = FirebaseAuth.instance;
    final userId = auth.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Transaction History"),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<PaymentTransaction>>(
        stream: paymentService.streamStudentTransactions(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    "No transactions yet",
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final transactions = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            separatorBuilder: (c, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return _buildTransactionCard(context, transaction, paymentService);
            },
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(
    BuildContext context,
    PaymentTransaction transaction,
    PaymentService paymentService,
  ) {
    final isCompleted = transaction.status == 'completed';
    final statusColor = isCompleted ? Colors.green : Colors.orange;

    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isCompleted ? Icons.check_circle : Icons.pending,
            color: statusColor,
            size: 24,
          ),
        ),
        title: Text(
          "Invoice Payment",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('dd MMM yyyy, h:mm a')
                    .format(TimezoneHelper.toMalaysiaTime(transaction.createdAt)),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor.shade200),
                    ),
                    child: Text(
                      transaction.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor.shade700,
                      ),
                    ),
                  ),
                  if (transaction.paymentMethod != 'manual') ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        transaction.paymentMethod.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: Text(
          "RM ${transaction.amount.toStringAsFixed(2)}",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
        ),
        onTap: () => _showTransactionDetails(context, transaction, paymentService),
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    PaymentTransaction transaction,
    PaymentService paymentService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Transaction Details"),
        content: FutureBuilder<Invoice?>(
          future: paymentService.getInvoice(transaction.invoiceId),
          builder: (context, invoiceSnapshot) {
            final invoice = invoiceSnapshot.data;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow("Transaction ID:", transaction.id),
                  _detailRow("Status:", transaction.status.toUpperCase()),
                  _detailRow("Amount:", "RM ${transaction.amount.toStringAsFixed(2)}"),
                  if (transaction.paypalAmount != null && transaction.paypalCurrency != null)
                    _detailRow(
                      "PayPal Charge:",
                      "${transaction.paypalCurrency} ${transaction.paypalAmount!.toStringAsFixed(2)}",
                    ),
                  if (transaction.exchangeRate != null)
                    _detailRow("Exchange Rate:", "1 MYR ≈ ${transaction.exchangeRate!.toStringAsFixed(4)} USD"),
                  _detailRow("Payment Method:", transaction.paymentMethod.toUpperCase()),
                  _detailRow(
                    "Date:",
                    DateFormat('dd MMM yyyy, h:mm a')
                        .format(TimezoneHelper.toMalaysiaTime(transaction.createdAt)),
                  ),
                  if (transaction.completedAt != null)
                    _detailRow(
                      "Completed:",
                      DateFormat('dd MMM yyyy, h:mm a')
                          .format(TimezoneHelper.toMalaysiaTime(transaction.completedAt!)),
                    ),
                  if (transaction.paypalOrderId != null)
                    _detailRow("PayPal Order ID:", transaction.paypalOrderId!),
                  if (invoice != null) ...[
                    const Divider(),
                    _detailRow(
                      "Invoice Month:",
                      DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month)),
                    ),
                    _detailRow(
                      "Due Date:",
                      DateFormat('dd MMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate)),
                    ),
                  ],
                  if (transaction.notes != null) ...[
                    const Divider(),
                    _detailRow("Notes:", transaction.notes!),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
          if (transaction.status == 'completed')
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _generateReceipt(context, transaction, paymentService);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1458a3)),
              child: const Text("Download Receipt", style: TextStyle(color: Colors.white)),
            ),
        ],
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
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateReceipt(
    BuildContext context,
    PaymentTransaction transaction,
    PaymentService paymentService,
  ) async {
    try {
      final invoice = await paymentService.getInvoice(transaction.invoiceId);
      if (invoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invoice not found"), backgroundColor: Colors.red),
        );
        return;
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Text(
                  'PAYMENT RECEIPT',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Tuition E-Classroom',
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 30),
                
                // Receipt Details
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Receipt Number:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(transaction.id, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 10),
                        pw.Text('Date:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(
                          DateFormat('MMM d, yyyy • h:mm a').format(
                            TimezoneHelper.toMalaysiaTime(
                              transaction.completedAt ?? transaction.createdAt,
                            ),
                          ),
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Student:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(transaction.studentName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 10),
                        pw.Text('Email:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(invoice.studentEmail, style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 30),
                
                // Invoice Details
                pw.Text(
                  'Invoice Details',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                    'Invoice Month: ${DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))}'),
                pw.Text(
                    'Due Date: ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))}'),
                pw.SizedBox(height: 20),
                
                // Subject Breakdown
                pw.Text(
                  'Subject Breakdown:',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                ...invoice.items.map((item) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              '${item.subjectName} - ${item.className}',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ),
                          pw.Text(
                            'RM ${item.price.toStringAsFixed(2)}',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    )),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                
                // Payment Summary
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Amount:',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'RM ${transaction.amount.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment Method:', style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                    pw.Text(
                      transaction.paymentMethod.toUpperCase(),
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                if (transaction.paypalOrderId != null) ...[
                  pw.SizedBox(height: 5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PayPal Order ID:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text(
                        transaction.paypalOrderId!,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 30),
                
                // Footer
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Thank you for your payment!',
                  style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'This is an official receipt for your records.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating receipt: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
