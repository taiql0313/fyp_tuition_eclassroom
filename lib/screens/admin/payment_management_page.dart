import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'generate_invoices_page.dart';
import 'payment_reminders_page.dart';

class PaymentManagementPage extends StatefulWidget {
  const PaymentManagementPage({super.key});

  @override
  State<PaymentManagementPage> createState() => _PaymentManagementPageState();
}

class _PaymentManagementPageState extends State<PaymentManagementPage> with SingleTickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Generate monthly invoices on page load (admin can trigger manually)
    _paymentService.checkAndSendReminders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment Management"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Invoices", icon: Icon(Icons.receipt_long)),
            Tab(text: "Transactions", icon: Icon(Icons.payment)),
            Tab(text: "Reports", icon: Icon(Icons.bar_chart)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: "Payment Reminders",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PaymentRemindersPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Generate Invoices",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GenerateInvoicesPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Generate Monthly Invoices (All Students)",
            onPressed: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text("Generating monthly invoices..."),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              try {
                await _paymentService.generateMonthlyInvoicesForAllStudents();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Monthly invoices generated successfully!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Error: ${e.toString()}"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInvoicesTab(),
          _buildTransactionsTab(),
          _buildReportsTab(),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab() {
    return StreamBuilder<List<Invoice>>(
      stream: _paymentService.streamAllInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  "No invoices found",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final invoices = snapshot.data!;
        final pendingCount = invoices.where((i) => i.status == 'pending').length;
        final paidCount = invoices.where((i) => i.status == 'paid').length;
        final overdueCount = invoices.where((i) => i.status == 'overdue').length;
        final totalRevenue = invoices.where((i) => i.status == 'paid').fold(0.0, (sum, i) => sum + i.totalAmount);

        return Column(
          children: [
            // Summary Cards
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[50],
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard("Pending", pendingCount.toString(), Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard("Paid", paidCount.toString(), Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard("Overdue", overdueCount.toString(), Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard("Revenue", "RM ${totalRevenue.toStringAsFixed(0)}", Colors.blue),
                  ),
                ],
              ),
            ),

            // Invoices List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: invoices.length,
                itemBuilder: (context, index) {
                  return _buildInvoiceCard(invoices[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    final statusColor = invoice.status == 'paid'
        ? Colors.green
        : invoice.status == 'overdue'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            invoice.status == 'paid'
                ? Icons.check_circle
                : invoice.status == 'overdue'
                    ? Icons.error
                    : Icons.pending,
            color: statusColor,
          ),
        ),
        title: Text(
          invoice.studentName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${DateFormat('MMMM yyyy').format(invoice.month)} • ${invoice.items.length} subject(s)"),
            const SizedBox(height: 4),
            Text(
              "Due: ${DateFormat('MMM d, yyyy').format(invoice.dueDate)}",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "RM ${invoice.totalAmount.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                invoice.status.toUpperCase(),
                style: TextStyle(
                  color: statusColor.shade700,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _showInvoiceDetails(invoice),
      ),
    );
  }

  void _showInvoiceDetails(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Invoice - ${DateFormat('MMMM yyyy').format(invoice.month)}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Student:", invoice.studentName),
              _detailRow("Email:", invoice.studentEmail),
              _detailRow("Due Date:", DateFormat('MMM d, yyyy').format(invoice.dueDate)),
              _detailRow("Status:", invoice.status.toUpperCase()),
              const Divider(),
              const Text("Subject Breakdown:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...invoice.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("${item.subjectName} - ${item.className}")),
                        Text("RM ${item.price.toStringAsFixed(2)}"),
                      ],
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    "RM ${invoice.totalAmount.toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          if (invoice.status == 'pending')
            ElevatedButton(
              onPressed: () => _showRecordManualPayment(invoice),
              child: const Text("Record Payment"),
            ),
          if (invoice.status == 'paid')
            ElevatedButton(
              onPressed: () => _exportInvoicePDF(invoice),
              child: const Text("Export PDF"),
            ),
        ],
      ),
    );
  }

  void _showRecordManualPayment(Invoice invoice) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Record Manual Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Amount: RM ${invoice.totalAmount.toStringAsFixed(2)}"),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: "Notes (Optional)",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _paymentService.recordManualPayment(
                  invoiceId: invoice.id,
                  studentId: invoice.studentId,
                  studentName: invoice.studentName,
                  amount: invoice.totalAmount,
                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context); // Close invoice details too
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Payment recorded successfully!"),
                      backgroundColor: Colors.green,
                    ),
                  );
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
            },
            child: const Text("Record"),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return StreamBuilder<List<PaymentTransaction>>(
      stream: _paymentService.streamAllTransactions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  "No transactions found",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final transactions = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            return _buildTransactionCard(transactions[index]);
          },
        );
      },
    );
  }

  Widget _buildTransactionCard(PaymentTransaction transaction) {
    final statusColor = transaction.status == 'completed'
        ? Colors.green
        : transaction.status == 'failed'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            transaction.status == 'completed'
                ? Icons.check_circle
                : transaction.status == 'failed'
                    ? Icons.error
                    : Icons.pending,
            color: statusColor,
          ),
        ),
        title: Text(
          transaction.studentName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM d, yyyy • h:mm a').format(transaction.createdAt)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    transaction.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    transaction.paymentMethod.toUpperCase(),
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Text(
          "RM ${transaction.amount.toStringAsFixed(2)}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildReportsTab() {
    return StreamBuilder<List<Invoice>>(
      stream: _paymentService.streamAllInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final invoices = snapshot.data ?? [];
        final transactions = <PaymentTransaction>[];
        
        // Calculate statistics
        final totalRevenue = invoices.where((i) => i.status == 'paid').fold(0.0, (sum, i) => sum + i.totalAmount);
        final pendingAmount = invoices.where((i) => i.status == 'pending').fold(0.0, (sum, i) => sum + i.totalAmount);
        final overdueAmount = invoices.where((i) => i.status == 'overdue').fold(0.0, (sum, i) => sum + i.totalAmount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Payment Statistics", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard("Total Revenue", "RM ${totalRevenue.toStringAsFixed(2)}", Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard("Pending", "RM ${pendingAmount.toStringAsFixed(2)}", Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard("Overdue", "RM ${overdueAmount.toStringAsFixed(2)}", Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard("Total Invoices", invoices.length.toString(), Colors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _exportPaymentReport(invoices, transactions),
                icon: const Icon(Icons.download),
                label: const Text("Export Payment Report (PDF)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1458a3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportInvoicePDF(Invoice invoice) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Student: ${invoice.studentName}'),
              pw.Text('Email: ${invoice.studentEmail}'),
              pw.Text('Month: ${DateFormat('MMMM yyyy').format(invoice.month)}'),
              pw.Text('Due Date: ${DateFormat('MMM d, yyyy').format(invoice.dueDate)}'),
              pw.SizedBox(height: 20),
              pw.Text('Subject Breakdown:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ...invoice.items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${item.subjectName} - ${item.className}'),
                        pw.Text('RM ${item.price.toStringAsFixed(2)}'),
                      ],
                    ),
                  )),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text('RM ${invoice.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _exportPaymentReport(List<Invoice> invoices, List<PaymentTransaction> transactions) async {
    final pdf = pw.Document();
    
    // Calculate statistics
    final totalRevenue = invoices.where((i) => i.status == 'paid').fold(0.0, (sum, i) => sum + i.totalAmount);
    final pendingAmount = invoices.where((i) => i.status == 'pending').fold(0.0, (sum, i) => sum + i.totalAmount);
    final overdueAmount = invoices.where((i) => i.status == 'overdue').fold(0.0, (sum, i) => sum + i.totalAmount);
    final paidCount = invoices.where((i) => i.status == 'paid').length;
    final pendingCount = invoices.where((i) => i.status == 'pending').length;
    final overdueCount = invoices.where((i) => i.status == 'overdue').length;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Text(
                'PAYMENT REPORT',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Generated: ${DateFormat('MMM d, yyyy, h:mm a').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 30),
              
              // Summary Table
              pw.Text(
                'Summary',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableCell('Metric', isHeader: true),
                      _buildTableCell('Count', isHeader: true),
                      _buildTableCell('Amount (RM)', isHeader: true),
                    ],
                  ),
                  _buildTableRow('Total Invoices', invoices.length.toString(), '-'),
                  _buildTableRow('Paid', paidCount.toString(), totalRevenue.toStringAsFixed(2)),
                  _buildTableRow('Pending', pendingCount.toString(), pendingAmount.toStringAsFixed(2)),
                  _buildTableRow('Overdue', overdueCount.toString(), overdueAmount.toStringAsFixed(2)),
                ],
              ),
              pw.SizedBox(height: 30),
              
              // Invoices Table
              pw.Text(
                'Invoice Details',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableCell('Student Name', isHeader: true),
                      _buildTableCell('Month', isHeader: true),
                      _buildTableCell('Amount', isHeader: true),
                      _buildTableCell('Due Date', isHeader: true),
                      _buildTableCell('Status', isHeader: true),
                    ],
                  ),
                  // Data rows (limit to 50 for performance)
                  ...invoices.take(50).map((invoice) => pw.TableRow(
                        children: [
                          _buildTableCell(invoice.studentName),
                          _buildTableCell(DateFormat('MMM yyyy').format(invoice.month)),
                          _buildTableCell(invoice.totalAmount.toStringAsFixed(2)),
                          _buildTableCell(DateFormat('MMM d').format(invoice.dueDate)),
                          _buildTableCell(
                            invoice.status.toUpperCase(),
                            color: invoice.status == 'paid'
                                ? PdfColors.green
                                : invoice.status == 'overdue'
                                    ? PdfColors.red
                                    : PdfColors.orange,
                          ),
                        ],
                      )),
                ],
              ),
              if (invoices.length > 50)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    '... and ${invoices.length - 50} more invoices',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                  ),
                ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  pw.TableRow _buildTableRow(String label, String count, String amount) {
    return pw.TableRow(
      children: [
        _buildTableCell(label),
        _buildTableCell(count),
        _buildTableCell(amount),
      ],
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
