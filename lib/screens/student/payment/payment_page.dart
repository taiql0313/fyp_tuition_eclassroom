import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/services/email_service.dart';
import 'package:fyp_tuition_eclassroom/services/blockchain_payment_service.dart';
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
  final BlockchainPaymentService _blockchainService = BlockchainPaymentService();
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

  Future<void> _sendReceiptEmail(String orderId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final txQuery = await _paymentService.getTransactionByOrderId(orderId, user.uid);
      if (txQuery != null) {
        await EmailService.sendReceiptForTransaction(txQuery);
      }
    } catch (e) {
      print('Failed to send receipt email: $e');
    }
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
    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Choose Payment Method",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Amount: RM ${invoice.totalAmount.toStringAsFixed(2)}",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.paypal, color: Colors.blue, size: 28),
              ),
              title: const Text("PayPal", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                "~USD ${_paymentService.convertMyrToUsd(invoice.totalAmount).toStringAsFixed(2)}",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.pop(context, 'paypal'),
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.currency_bitcoin, color: Colors.orange, size: 28),
              ),
              title: const Text("Blockchain (ETH)", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                "~${_blockchainService.convertMyrToEth(invoice.totalAmount).toStringAsFixed(6)} ETH via Ganache",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.pop(context, 'blockchain'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (method == null || !mounted) return;

    if (method == 'paypal') {
      _handlePayPalPayment(invoice);
    } else if (method == 'blockchain') {
      _handleBlockchainPayment(invoice);
    }
  }

  Future<void> _handlePayPalPayment(Invoice invoice) async {
    try {
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

      final user = _auth.currentUser;
      if (user == null) return;

      final orderData = await _paymentService.createPayPalOrder(
        invoiceId: invoice.id,
        amount: invoice.totalAmount,
        studentId: user.uid,
        studentName: user.displayName ?? 'Student',
      );

      if (!mounted) return;
      Navigator.pop(context);

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

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayPalWebViewPage(approvalUrl: approvalUrl),
        ),
      );

      if (!mounted || result == null) return;

      if (result is Map && result['status'] == 'success') {
        final orderId = (result['orderId'] as String?) ?? createdOrderId;

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
          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Payment completed successfully! Receipt sent to your email."),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );

          _sendReceiptEmail(orderId);
          _loadPaymentData();
        } catch (e) {
          if (!mounted) return;
          Navigator.pop(context);

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Payment was cancelled."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleBlockchainPayment(Invoice invoice) async {
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => _BlockchainPaymentPage(
          invoice: invoice,
          blockchainService: _blockchainService,
        ),
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      final String? txId = result['transactionId'] as String?;
      if (txId != null) {
        try {
          final txDoc = await FirebaseFirestore.instance
              .collection('payment_transactions')
              .doc(txId)
              .get();
          if (txDoc.exists) {
            final txData = txDoc.data()!;
            final tx = PaymentTransaction.fromMap(txDoc.id, txData);
            await EmailService.sendReceiptForTransaction(tx);
          }
        } catch (e) {
          print('Failed to send blockchain receipt email: $e');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Blockchain payment completed successfully! Receipt sent to your email."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      _loadPaymentData();
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "PayPal: ~USD ${usdAmount.toStringAsFixed(2)}  |  "
                                  "ETH: ~${_blockchainService.convertMyrToEth(_nextDueInvoice!.totalAmount).toStringAsFixed(6)} ETH",
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
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

class _BlockchainPaymentPage extends StatefulWidget {
  final Invoice invoice;
  final BlockchainPaymentService blockchainService;

  const _BlockchainPaymentPage({
    required this.invoice,
    required this.blockchainService,
  });

  @override
  State<_BlockchainPaymentPage> createState() => _BlockchainPaymentPageState();
}

class _BlockchainPaymentPageState extends State<_BlockchainPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isProcessing = false;
  bool _obscureKey = true;
  String? _walletBalance;

  @override
  void dispose() {
    _addressController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _checkBalance() async {
    final address = _addressController.text.trim();
    if (address.isEmpty || !address.startsWith('0x') || address.length != 42) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid Ethereum address"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final balance = await widget.blockchainService.getBalance(address);
      final ethBalance = balance.getInWei / BigInt.from(10).pow(18);
      setState(() {
        _walletBalance = ethBalance.toStringAsFixed(4);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to fetch balance: ${e.toString().replaceFirst('Exception: ', '')}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ethAmount = widget.blockchainService.convertMyrToEth(widget.invoice.totalAmount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Amount: RM ${widget.invoice.totalAmount.toStringAsFixed(2)}"),
            const SizedBox(height: 4),
            Text("ETH Equivalent: ${ethAmount.toStringAsFixed(6)} ETH"),
            const SizedBox(height: 4),
            Text(
              "From: ${_addressController.text.trim().substring(0, 10)}...${_addressController.text.trim().substring(36)}",
            ),
            const SizedBox(height: 4),
            Text(
              "To: ${BlockchainPaymentService.receiverAddress.substring(0, 10)}...${BlockchainPaymentService.receiverAddress.substring(36)}",
            ),
            const SizedBox(height: 12),
            Text(
              "This transaction cannot be reversed.",
              style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("Confirm & Pay"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final result = await widget.blockchainService.processBlockchainPayment(
        invoiceId: widget.invoice.id,
        amountMyr: widget.invoice.totalAmount,
        studentId: user.uid,
        studentName: user.displayName ?? 'Student',
        senderAddress: _addressController.text.trim(),
        privateKey: _privateKeyController.text.trim(),
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text("Payment Successful!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Amount: ${result['ethAmount']} ETH"),
              const SizedBox(height: 8),
              const Text("Transaction Hash:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                result['txHash'] as String,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'transactionId': result['transactionId'],
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Payment Failed"),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ethAmount = widget.blockchainService.convertMyrToEth(widget.invoice.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Blockchain Payment"),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xffE65100), Color(0xffFF9800)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.currency_bitcoin, color: Colors.white, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          "ETH Payment",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "${ethAmount.toStringAsFixed(6)} ETH",
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "RM ${widget.invoice.totalAmount.toStringAsFixed(2)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Network: Ganache Local (127.0.0.1:7545)",
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Sending to: ${BlockchainPaymentService.receiverAddress}",
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                "Your Wallet Details",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: "Wallet Address",
                  hintText: "0x...",
                  prefixIcon: const Icon(Icons.account_balance_wallet),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: "Check Balance",
                    onPressed: _checkBalance,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Wallet address is required';
                  if (!value.trim().startsWith('0x') || value.trim().length != 42) {
                    return 'Invalid Ethereum address format';
                  }
                  return null;
                },
              ),

              if (_walletBalance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "Balance: $_walletBalance ETH",
                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _privateKeyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: "Private Key",
                  hintText: "Enter your private key",
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Private key is required';
                  final key = value.trim().startsWith('0x') ? value.trim().substring(2) : value.trim();
                  if (key.length != 64) return 'Invalid private key length';
                  return null;
                },
              ),

              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your private key is never stored and is only used for this transaction.",
                        style: TextStyle(color: Colors.amber.shade800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _processPayment,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isProcessing ? "Processing..." : "Pay ${ethAmount.toStringAsFixed(6)} ETH",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    disabledBackgroundColor: Colors.orange.shade300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
