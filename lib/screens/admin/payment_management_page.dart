import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
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

class _PaymentManagementPageState extends State<PaymentManagementPage>
    with SingleTickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  late TabController _tabController;

  // Invoice filters
  final TextEditingController _invoiceSearchController = TextEditingController();
  String _invoiceSearchQuery = '';
  String _invoiceStatusFilter = 'All';
  int _invoiceMonthFilter = 0; // 0 = All
  int _invoiceYearFilter = 0; // 0 = All

  // Transaction filters
  final TextEditingController _transactionSearchController = TextEditingController();
  String _transactionSearchQuery = '';
  DateTimeRange? _transactionDateRange;
  String _transactionStatusFilter = 'All';

  // Cached data for filtering without rebuild
  List<Invoice> _allInvoices = [];
  List<PaymentTransaction> _allTransactions = [];

  static const Color _primaryColor = Color(0xff1458a3);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _paymentService.checkAndSendReminders();

    // Listen to text changes without calling setState immediately
    _invoiceSearchController.addListener(_onInvoiceSearchChanged);
    _transactionSearchController.addListener(_onTransactionSearchChanged);
  }

  void _onInvoiceSearchChanged() {
    final query = _invoiceSearchController.text.trim().toLowerCase();
    if (query != _invoiceSearchQuery) {
      setState(() => _invoiceSearchQuery = query);
    }
  }

  void _onTransactionSearchChanged() {
    final query = _transactionSearchController.text.trim().toLowerCase();
    if (query != _transactionSearchQuery) {
      setState(() => _transactionSearchQuery = query);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _invoiceSearchController.removeListener(_onInvoiceSearchChanged);
    _transactionSearchController.removeListener(_onTransactionSearchChanged);
    _invoiceSearchController.dispose();
    _transactionSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
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

  PreferredSizeWidget _buildAppBar() {
    final theme = Theme.of(context);
    return AppBar(
      elevation: 0,
      title: const Text(
        "Payment Management",
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
      foregroundColor: theme.appBarTheme.foregroundColor ?? Colors.white,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(text: "Invoices", icon: Icon(Icons.receipt_long, size: 20)),
          Tab(text: "Transactions", icon: Icon(Icons.payment, size: 20)),
          Tab(text: "Reports", icon: Icon(Icons.bar_chart, size: 20)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: "Payment Reminders",
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentRemindersPage()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: "Generate Invoices",
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GenerateInvoicesPage()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: "Generate Monthly Invoices (All Students)",
          onPressed: _generateMonthlyInvoices,
        ),
      ],
    );
  }

  Future<void> _generateMonthlyInvoices() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
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
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============ INVOICES TAB ============

  Widget _buildInvoicesTab() {
    return Column(
      children: [
        // Keep transactions available for payment method badges
        StreamBuilder<List<PaymentTransaction>>(
          stream: _paymentService.streamAllTransactions(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _allTransactions = snapshot.data!;
            }
            return const SizedBox.shrink();
          },
        ),
        // Filter section (outside StreamBuilder)
        _buildInvoiceFilters(),
        // Data list
        Expanded(
          child: StreamBuilder<List<Invoice>>(
            stream: _paymentService.streamAllInvoices(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _allInvoices.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasData) {
                _allInvoices = snapshot.data!;
              }

              if (_allInvoices.isEmpty) {
                return _buildEmptyState(
                  context,
                  Icons.receipt_long,
                  "No invoices found",
                );
              }

              final filtered = _filterInvoices(_allInvoices);
              return _buildInvoiceList(filtered);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceFilters() {
    final theme = Theme.of(context);
    final hasFilters = _invoiceSearchQuery.isNotEmpty ||
        _invoiceStatusFilter != 'All' ||
        _invoiceMonthFilter != 0 ||
        _invoiceYearFilter != 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
        // Search row
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final searchField = TextField(
              controller: _invoiceSearchController,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search student name or email...',
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                suffixIcon: _invoiceSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20, color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () {
                          _invoiceSearchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryColor, width: 1.5),
                ),
              ),
            );

            final monthDropdown = _buildInvoiceMonthDropdown();
            final yearDropdown = _buildInvoiceYearDropdown();
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 140, child: monthDropdown),
                SizedBox(width: 110, child: yearDropdown),
                if (hasFilters)
                  IconButton(
                    onPressed: _clearInvoiceFilters,
                    icon: const Icon(Icons.filter_alt_off, color: Colors.red),
                    tooltip: 'Clear all filters',
                  ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
          const SizedBox(height: 12),
        // Status chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildStatusChip('All', _invoiceStatusFilter, (s) {
              setState(() => _invoiceStatusFilter = s);
            }),
            _buildStatusChip('pending', _invoiceStatusFilter, (s) {
              setState(() => _invoiceStatusFilter = s);
            }, color: Colors.orange),
            _buildStatusChip('paid', _invoiceStatusFilter, (s) {
              setState(() => _invoiceStatusFilter = s);
            }, color: Colors.green),
            _buildStatusChip('overdue', _invoiceStatusFilter, (s) {
              setState(() => _invoiceStatusFilter = s);
            }, color: Colors.red),
          ],
        ),
        ],
      ),
    );
  }

  Widget _buildInvoiceList(List<Invoice> invoices) {
    final pendingCount = _allInvoices.where((i) => i.status == 'pending').length;
    final paidCount = _allInvoices.where((i) => i.status == 'paid').length;
    final overdueCount = _allInvoices.where((i) => i.status == 'overdue').length;
    final totalRevenue =
        _allInvoices.where((i) => i.status == 'paid').fold(0.0, (sum, i) => sum + i.totalAmount);

    return Column(
      children: [
        // Summary cards
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildMiniStatCard('Pending', pendingCount, Colors.orange),
              const SizedBox(width: 8),
              _buildMiniStatCard('Paid', paidCount, Colors.green),
              const SizedBox(width: 8),
              _buildMiniStatCard('Overdue', overdueCount, Colors.red),
              const SizedBox(width: 8),
              _buildMiniStatCard('Revenue', 'RM ${totalRevenue.toStringAsFixed(0)}', _primaryColor),
            ],
          ),
        ),
        // Invoice list
        Expanded(
          child:               invoices.isEmpty
              ? Center(
                  child: Text(
                    'No invoices match filters',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: invoices.length,
                  itemBuilder: (context, index) => _buildInvoiceCard(invoices[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildMiniStatCard(String label, dynamic value, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    final theme = Theme.of(context);
    final statusColor = invoice.status == 'paid'
        ? Colors.green
        : invoice.status == 'overdue'
            ? Colors.red
            : Colors.orange;
    final paymentMethod = _getInvoicePaymentMethod(invoice);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showInvoiceDetails(invoice),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  invoice.status == 'paid'
                      ? Icons.check_circle_outline
                      : invoice.status == 'overdue'
                          ? Icons.warning_amber_rounded
                          : Icons.schedule,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.studentName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('MMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))} • ${invoice.items.length} subject(s)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    Text(
                      'Due: ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Amount & status & action
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'RM ${invoice.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (invoice.status != 'paid')
                        InkWell(
                          onTap: () => _showMarkAsPaidDialog(invoice),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, size: 12, color: Colors.blue),
                                SizedBox(width: 4),
                                Text(
                                  'MARK PAID',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (invoice.status == 'paid' && paymentMethod != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: paymentMethod == 'paypal'
                                ? Colors.indigo.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: paymentMethod == 'paypal'
                                  ? Colors.indigo.withOpacity(0.3)
                                  : Colors.green.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                paymentMethod == 'paypal'
                                    ? Icons.account_balance_wallet_outlined
                                    : Icons.payments_outlined,
                                size: 12,
                                color: paymentMethod == 'paypal'
                                    ? Colors.indigo
                                    : Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                paymentMethod == 'paypal' ? 'PAYPAL' : 'CASH',
                                style: TextStyle(
                                  color: paymentMethod == 'paypal'
                                      ? Colors.indigo
                                      : Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (invoice.status != 'paid' ||
                          (invoice.status == 'paid' && paymentMethod != null))
                        const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          invoice.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _getInvoicePaymentMethod(Invoice invoice) {
    if (invoice.status != 'paid') return null;
    if (_allTransactions.isEmpty) return null;

    PaymentTransaction? matched;
    final paymentId = invoice.paymentTransactionId;
    if (paymentId != null && paymentId.isNotEmpty) {
      for (var tx in _allTransactions) {
        if (tx.id == paymentId) {
          matched = tx;
          break;
        }
      }
    }

    if (matched == null) {
      for (var tx in _allTransactions) {
        if (tx.invoiceId == invoice.id && tx.status == 'completed') {
          matched = tx;
          break;
        }
      }
    }

    final method = matched?.paymentMethod.toLowerCase();
    if (method == null || method.isEmpty) return null;
    if (method == 'manual' || method == 'cash') return 'cash';
    if (method == 'paypal') return 'paypal';
    return method;
  }

  void _showMarkAsPaidDialog(Invoice invoice) {
    final notesController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.payments_outlined, color: Colors.green),
            ),
            const SizedBox(width: 12),
            const Text('Mark as Paid (Cash)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student: ${invoice.studentName}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'Amount: RM ${invoice.totalAmount.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            Text(
              'Month: ${DateFormat('MMMM yyyy').format(invoice.month)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g., Cash received on Jan 24',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will mark the invoice as paid via cash/manual payment.',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _markAsPaidCash(invoice, notesController.text.trim());
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirm Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsPaidCash(Invoice invoice, String notes) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Processing payment...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      await _paymentService.recordManualPayment(
        invoiceId: invoice.id,
        studentId: invoice.studentId,
        studentName: invoice.studentName,
        amount: invoice.totalAmount,
        notes: notes.isNotEmpty ? 'Cash payment - $notes' : 'Cash payment',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Payment recorded for ${invoice.studentName}'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============ TRANSACTIONS TAB ============

  Widget _buildTransactionsTab() {
    return Column(
      children: [
        _buildTransactionFilters(),
        Expanded(
          child: StreamBuilder<List<PaymentTransaction>>(
            stream: _paymentService.streamAllTransactions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _allTransactions.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasData) {
                _allTransactions = snapshot.data!;
              }

              if (_allTransactions.isEmpty) {
                return _buildEmptyState(context, Icons.payment, "No transactions found");
              }

              final filtered = _filterTransactions(_allTransactions);
              return _buildTransactionList(filtered);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionFilters() {
    final theme = Theme.of(context);
    final hasFilters = _transactionSearchQuery.isNotEmpty ||
        _transactionDateRange != null ||
        _transactionStatusFilter != 'All';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final searchField = TextField(
              controller: _transactionSearchController,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search student name...',
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                suffixIcon: _transactionSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20, color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () {
                          _transactionSearchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _primaryColor, width: 1.5),
                ),
              ),
            );

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDateButton(_transactionDateRange, _pickTransactionDateRange),
                if (hasFilters) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _clearTransactionFilters,
                    icon: const Icon(Icons.filter_alt_off, color: Colors.red),
                    tooltip: 'Clear all filters',
                  ),
                ],
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
          const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildStatusChip('All', _transactionStatusFilter, (s) {
              setState(() => _transactionStatusFilter = s);
            }),
            _buildStatusChip('pending', _transactionStatusFilter, (s) {
              setState(() => _transactionStatusFilter = s);
            }, color: Colors.orange),
            _buildStatusChip('completed', _transactionStatusFilter, (s) {
              setState(() => _transactionStatusFilter = s);
            }, color: Colors.green, label: 'Paid'),
            _buildStatusChip('failed', _transactionStatusFilter, (s) {
              setState(() => _transactionStatusFilter = s);
            }, color: Colors.red),
            if (_transactionDateRange != null)
              Chip(
                label: Text(
                  '${DateFormat('MMM d').format(TimezoneHelper.toMalaysiaTime(_transactionDateRange!.start))} - ${DateFormat('MMM d').format(TimezoneHelper.toMalaysiaTime(_transactionDateRange!.end))}',
                  style: const TextStyle(fontSize: 11),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => setState(() => _transactionDateRange = null),
                backgroundColor: _primaryColor.withOpacity(0.1),
                labelStyle: const TextStyle(color: _primaryColor),
              ),
          ],
        ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<PaymentTransaction> transactions) {
    final pendingCount = _allTransactions.where((t) => t.status == 'pending').length;
    final completedCount = _allTransactions.where((t) => t.status == 'completed').length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildMiniStatCard('Pending', pendingCount, Colors.orange),
              const SizedBox(width: 8),
              _buildMiniStatCard('Completed', completedCount, Colors.green),
            ],
          ),
        ),
        Expanded(
          child: transactions.isEmpty
              ? Center(
                  child: Text(
                    'No transactions match filters',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) => _buildTransactionCard(transactions[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(PaymentTransaction transaction) {
    final statusColor = transaction.status == 'completed'
        ? Colors.green
        : transaction.status == 'failed'
            ? Colors.red
            : Colors.orange;

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                transaction.status == 'completed'
                    ? Icons.check_circle_outline
                    : transaction.status == 'failed'
                        ? Icons.error_outline
                        : Icons.schedule,
                color: statusColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a')
                        .format(TimezoneHelper.toMalaysiaTime(transaction.createdAt)),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transaction.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transaction.paymentMethod.toUpperCase(),
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              'RM ${transaction.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ============ REPORTS TAB ============

  Widget _buildReportsTab() {
    return StreamBuilder<List<Invoice>>(
      stream: _paymentService.streamAllInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final invoices = snapshot.data ?? [];
        final totalRevenue =
            invoices.where((i) => i.status == 'paid').fold(0.0, (sum, i) => sum + i.totalAmount);
        final pendingAmount =
            invoices.where((i) => i.status == 'pending').fold(0.0, (sum, i) => sum + i.totalAmount);
        final overdueAmount =
            invoices.where((i) => i.status == 'overdue').fold(0.0, (sum, i) => sum + i.totalAmount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Payment Statistics",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
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
                    child: _buildStatCard("Total Invoices", invoices.length.toString(), _primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _exportPaymentReport(invoices, []),
                  icon: const Icon(Icons.download),
                  label: const Text("Export Payment Report (PDF)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ============ HELPER WIDGETS ============

  Widget _buildInvoiceMonthDropdown() {
    final theme = Theme.of(context);
    final monthLabels = List.generate(
      12,
      (index) => DateFormat('MMM').format(DateTime(2020, index + 1, 1)),
    );

    return DropdownButtonFormField<int>(
      value: _invoiceMonthFilter,
      decoration: InputDecoration(
        labelText: 'Month',
        filled: true,
        fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('All')),
        ...List.generate(
          12,
          (index) => DropdownMenuItem(
            value: index + 1,
            child: Text(monthLabels[index]),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _invoiceMonthFilter = value ?? 0),
    );
  }

  Widget _buildInvoiceYearDropdown() {
    final theme = Theme.of(context);
    final years = _getInvoiceYears();
    final selectedYear = years.contains(_invoiceYearFilter) ? _invoiceYearFilter : 0;

    return DropdownButtonFormField<int>(
      value: selectedYear,
      decoration: InputDecoration(
        labelText: 'Year',
        filled: true,
        fillColor: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('All')),
        ...years.map((year) => DropdownMenuItem(value: year, child: Text(year.toString()))),
      ],
      onChanged: (value) => setState(() => _invoiceYearFilter = value ?? 0),
    );
  }

  List<int> _getInvoiceYears() {
    final now = DateTime.now().year;
    final years = _allInvoices.map((i) => i.month.year).toSet().toList()..sort();
    if (years.isEmpty) {
      return [now - 1, now, now + 1];
    }
    return years;
  }

  Widget _buildDateButton(DateTimeRange? range, VoidCallback onPressed) {
    final theme = Theme.of(context);
    final isSelected = range != null;
    return Material(
      color: isSelected ? _primaryColor : (theme.colorScheme.surfaceContainerHighest),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range,
                size: 18,
                color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Date',
                style: TextStyle(
                  color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, String selected, Function(String) onSelect,
      {Color? color, String? label}) {
    final isSelected = selected == status;
    final displayLabel = label ?? (status == 'All' ? 'All' : status[0].toUpperCase() + status.substring(1));
    final chipColor = color ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          displayLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : chipColor,
          ),
        ),
        selected: isSelected,
        selectedColor: chipColor,
        backgroundColor: chipColor.withOpacity(0.1),
        side: BorderSide.none,
        onSelected: (_) => onSelect(status),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, IconData icon, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16)),
        ],
      ),
    );
  }

  // ============ FILTER LOGIC ============

  Future<void> _pickTransactionDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _transactionDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _transactionDateRange = picked);
    }
  }

  List<Invoice> _filterInvoices(List<Invoice> invoices) {
    return invoices.where((invoice) {
      // Search filter
      if (_invoiceSearchQuery.isNotEmpty) {
        final name = invoice.studentName.toLowerCase();
        final email = invoice.studentEmail.toLowerCase();
        if (!name.contains(_invoiceSearchQuery) && !email.contains(_invoiceSearchQuery)) {
          return false;
        }
      }

      // Status filter
      if (_invoiceStatusFilter != 'All' && invoice.status != _invoiceStatusFilter) {
        return false;
      }

      // Month/Year filter (invoice month)
      final invoiceMonth = TimezoneHelper.toMalaysiaTime(invoice.month);
      if (_invoiceMonthFilter != 0 && invoiceMonth.month != _invoiceMonthFilter) {
        return false;
      }
      if (_invoiceYearFilter != 0 && invoiceMonth.year != _invoiceYearFilter) {
        return false;
      }

      return true;
    }).toList();
  }

  List<PaymentTransaction> _filterTransactions(List<PaymentTransaction> transactions) {
    return transactions.where((tx) {
      if (_transactionSearchQuery.isNotEmpty) {
        final name = tx.studentName.toLowerCase();
        if (!name.contains(_transactionSearchQuery)) {
          return false;
        }
      }

      if (_transactionStatusFilter != 'All' && tx.status != _transactionStatusFilter) {
        return false;
      }

      if (_transactionDateRange != null) {
        final rangeStart = TimezoneHelper.toMalaysiaTime(DateTime(
          _transactionDateRange!.start.year,
          _transactionDateRange!.start.month,
          _transactionDateRange!.start.day,
        ));
        final rangeEnd = TimezoneHelper.toMalaysiaTime(DateTime(
          _transactionDateRange!.end.year,
          _transactionDateRange!.end.month,
          _transactionDateRange!.end.day,
          23,
          59,
          59,
        ));
        final txTime = TimezoneHelper.toMalaysiaTime(tx.createdAt);
        if (txTime.isBefore(rangeStart) || txTime.isAfter(rangeEnd)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _clearInvoiceFilters() {
    _invoiceSearchController.clear();
    setState(() {
      _invoiceSearchQuery = '';
      _invoiceStatusFilter = 'All';
      _invoiceMonthFilter = 0;
      _invoiceYearFilter = 0;
    });
  }

  void _clearTransactionFilters() {
    _transactionSearchController.clear();
    setState(() {
      _transactionSearchQuery = '';
      _transactionDateRange = null;
      _transactionStatusFilter = 'All';
    });
  }

  // ============ DIALOGS ============

  void _showInvoiceDetails(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Invoice - ${DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))}",
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Student:", invoice.studentName),
              _detailRow("Email:", invoice.studentEmail),
              _detailRow(
                "Due Date:",
                DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate)),
              ),
              _detailRow("Status:", invoice.status.toUpperCase()),
              const Divider(height: 24),
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
              const Divider(height: 24),
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
          if (invoice.status == 'pending' || invoice.status == 'overdue')
            ElevatedButton(
              onPressed: () => _showRecordManualPayment(invoice),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text("Record Payment"),
            ),
          if (invoice.status == 'paid')
            ElevatedButton(
              onPressed: () => _exportInvoicePDF(invoice),
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  Navigator.pop(context);
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
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text("Record"),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ============ PDF EXPORT ============

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
              pw.Text(
                'Month: ${DateFormat('MMMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))}',
              ),
              pw.Text(
                'Due Date: ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))}',
              ),
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
                  pw.Text('RM ${invoice.totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _exportPaymentReport(List<Invoice> invoices, List<PaymentTransaction> transactions) async {
    final pdf = pw.Document();

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
              pw.Text('PAYMENT REPORT', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(
                  'Generated: ${DateFormat('MMM d, yyyy, h:mm a').format(TimezoneHelper.getMalaysiaTime())}',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 30),
              pw.Text('Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
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
              pw.Text('Invoice Details', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
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
                  ...invoices.take(50).map((invoice) => pw.TableRow(
                        children: [
                          _buildTableCell(invoice.studentName),
                          _buildTableCell(
                              DateFormat('MMM yyyy').format(TimezoneHelper.toMalaysiaTime(invoice.month))),
                          _buildTableCell(invoice.totalAmount.toStringAsFixed(2)),
                          _buildTableCell(
                              DateFormat('MMM d').format(TimezoneHelper.toMalaysiaTime(invoice.dueDate))),
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
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
}
