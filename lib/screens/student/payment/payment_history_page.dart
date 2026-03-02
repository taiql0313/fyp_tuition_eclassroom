import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';

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
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                _showReceiptOptions(context, transaction, paymentService);
              },
              icon: const Icon(Icons.receipt_long, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff1458a3),
                foregroundColor: Colors.white,
              ),
              label: const Text("Receipt"),
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

  void _showReceiptOptions(
    BuildContext context,
    PaymentTransaction transaction,
    PaymentService paymentService,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Payment Receipt",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "RM ${transaction.amount.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print, color: Color(0xff1458a3)),
                ),
                title: const Text("Print Receipt"),
                subtitle: const Text("Send to printer or save as PDF"),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleReceipt(context, transaction, paymentService, 'print');
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.share, color: Colors.green),
                ),
                title: const Text("Share Receipt"),
                subtitle: const Text("Share via WhatsApp, email, etc."),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleReceipt(context, transaction, paymentService, 'share');
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.save_alt, color: Colors.orange),
                ),
                title: const Text("Save to Device"),
                subtitle: const Text("Save PDF to Downloads folder"),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleReceipt(context, transaction, paymentService, 'save');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildReceiptPdf(
    PaymentTransaction transaction,
    Invoice invoice,
  ) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xff1458a3),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PAYMENT RECEIPT',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Tuition E-Classroom',
                      style: const pw.TextStyle(fontSize: 14, color: PdfColors.white),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

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
              pw.SizedBox(height: 24),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xfff5f5f5),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Invoice Details',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Invoice Month: ${DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))}',
                    ),
                    pw.Text(
                      'Due Date: ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))}',
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Text(
                'Subject Breakdown:',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xffe3f2fd)),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Subject / Class', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  ...invoice.items.map((item) => pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('${item.subjectName} - ${item.className}', style: const pw.TextStyle(fontSize: 11)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('RM ${item.price.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 11), textAlign: pw.TextAlign.right),
                          ),
                        ],
                      )),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xfff5f5f5)),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'RM ${transaction.amount.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

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
                    pw.Text(transaction.paypalOrderId!, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
              if (transaction.paypalAmount != null && transaction.paypalCurrency != null) ...[
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('PayPal Charge:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(
                      '${transaction.paypalCurrency} ${transaction.paypalAmount!.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
              pw.SizedBox(height: 30),

              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'Thank you for your payment!',
                  style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  'This is an official receipt for your records.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _handleReceipt(
    BuildContext context,
    PaymentTransaction transaction,
    PaymentService paymentService,
    String action,
  ) async {
    try {
      final invoice = await paymentService.getInvoice(transaction.invoiceId);
      if (invoice == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invoice not found"), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final pdfBytes = await _buildReceiptPdf(transaction, invoice);
      final fileName = 'Receipt_${transaction.id.substring(0, 8)}.pdf';

      if (action == 'print') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      } else if (action == 'share') {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Payment Receipt - RM ${transaction.amount.toStringAsFixed(2)}',
          subject: 'Tuition Payment Receipt',
        );
      } else if (action == 'save') {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Receipt saved to ${file.path}"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Open',
                textColor: Colors.white,
                onPressed: () => OpenFile.open(file.path),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
