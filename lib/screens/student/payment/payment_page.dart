import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'payment_history_page.dart';
import 'paypal_webview_page.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final PaymentService _paymentService = PaymentService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  double? _outstandingBalance;
  Invoice? _nextDueInvoice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentData();
    // Check for reminders when page loads
    _paymentService.checkAndSendReminders();
  }

  Future<void> _loadPaymentData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final balance = await _paymentService.getOutstandingBalance(user.uid);
      final pendingInvoices = await _paymentService.getPendingInvoices(user.uid);
      
      setState(() {
        _outstandingBalance = balance;
        _nextDueInvoice = pendingInvoices.isNotEmpty 
            ? pendingInvoices.first 
            : null;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading payment data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePayNow(Invoice invoice) async {
    try {
      // Show loading
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
                  Text("Processing payment..."),
                ],
              ),
            ),
          ),
        ),
      );

      // Create PayPal order
      final user = _auth.currentUser;
      if (user == null) return;

      final orderData = await _paymentService.createPayPalOrder(
        invoiceId: invoice.id,
        amount: invoice.totalAmount,
        studentId: user.uid,
        studentName: user.displayName ?? 'Student',
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      final approvalUrl = orderData['approvalUrl'] as String;
      final createdOrderId = orderData['orderId'] as String;

      if (approvalUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid PayPal checkout URL"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Open PayPal in an in-app WebView so we can intercept the redirect
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayPalWebViewPage(approvalUrl: approvalUrl),
        ),
      );

      if (!mounted || result == null) return;

      if (result is Map && result['status'] == 'success') {
        final orderId = (result['orderId'] as String?) ?? createdOrderId;

        // Show loading while verifying
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
                    Text("Verifying payment..."),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          await _paymentService.capturePayPalPayment(orderId).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw Exception('Payment verification timed out after 20 seconds. Please try again.');
            },
          );

          if (!mounted) return;
          Navigator.pop(context); // Close loading

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Payment completed successfully!"),
              backgroundColor: Colors.green,
            ),
          );

          _loadPaymentData();
        } catch (e) {
          if (!mounted) return;
          Navigator.pop(context); // Close loading

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Payment Verification Failed"),
              content: Text(
                e.toString().replaceFirst('Exception: ', ''),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        // User cancelled payment in PayPal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment was cancelled."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog if still open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final usdAmount = _nextDueInvoice != null
        ? _paymentService.convertMyrToUsd(_nextDueInvoice!.totalAmount)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fees & Payments"),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1. Summary Card ---
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff1458a3), Color(0xff4a90e2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff1458a3).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Outstanding Balance",
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "RM ${(_outstandingBalance ?? 0.0).toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_nextDueInvoice != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Next Due Date", style: TextStyle(color: Colors.white70, fontSize: 11)),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM d, yyyy').format(
                                        TimezoneHelper.toMalaysiaTime(_nextDueInvoice!.dueDate),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            if (_nextDueInvoice != null && _outstandingBalance != null && _outstandingBalance! > 0)
                              ElevatedButton.icon(
                                onPressed: () => _handlePayNow(_nextDueInvoice!),
                                icon: const Icon(Icons.payment, size: 18),
                                label: const Text("Pay Now"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xff1458a3),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              )
                            else if (_outstandingBalance == 0 || _outstandingBalance == null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "All Paid",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        if (usdAmount != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              "PayPal charges in USD: ~USD ${usdAmount.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  // --- 2. Action Cards ---
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionCard(
                          context,
                          title: "Payment History",
                          subtitle: "View Past Transactions",
                          icon: Icons.history,
                          color: Colors.blue,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PaymentHistoryPage()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildActionCard(
                          context,
                          title: "Invoices",
                          subtitle: "View All Invoices",
                          icon: Icons.receipt_long,
                          color: Colors.orange,
                          onTap: () {
                            // Navigate to invoices page
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _InvoicesPage(paymentService: _paymentService),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                  const Text("Recent Transactions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  // --- 3. Recent Transactions List ---
                  StreamBuilder<List<PaymentTransaction>>(
                    stream: _paymentService.streamStudentTransactions(_auth.currentUser?.uid ?? ''),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              "No transactions yet",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        );
                      }

                      final transactions = snapshot.data!.take(5).toList();
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          return _buildTransactionTile(transactions[index]);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(PaymentTransaction transaction) {
    final isCompleted = transaction.status == 'completed';
    
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCompleted ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isCompleted ? Icons.check_circle : Icons.pending,
            color: isCompleted ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          "Invoice Payment",
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('MMM d, yyyy • h:mm a')
                  .format(TimezoneHelper.toMalaysiaTime(transaction.createdAt)),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                transaction.status.toUpperCase(),
                style: TextStyle(
                  color: isCompleted ? Colors.green.shade700 : Colors.orange.shade700,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Text(
          "RM ${transaction.amount.toStringAsFixed(2)}",
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// Invoices Page
class _InvoicesPage extends StatelessWidget {
  final PaymentService paymentService;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  _InvoicesPage({required this.paymentService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Invoices"),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Invoice>>(
        stream: paymentService.streamStudentInvoices(_auth.currentUser?.uid ?? ''),
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
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: invoices.length,
            itemBuilder: (context, index) {
              final invoice = invoices[index];
              return _buildInvoiceCard(context, invoice);
            },
          );
        },
      ),
    );
  }

  Widget _buildInvoiceCard(BuildContext context, Invoice invoice) {
    final statusColor = invoice.status == 'paid'
        ? Colors.green
        : invoice.status == 'overdue'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          invoice.status == 'paid' ? Icons.check_circle : Icons.pending,
          color: statusColor,
        ),
        title: Text(
          DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Due: ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))}",
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Subject Breakdown:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...invoice.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${item.subjectName} - ${item.className}"),
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
        ],
      ),
    );
  }
}
