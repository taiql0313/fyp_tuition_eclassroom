import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class PaymentReportPage extends StatefulWidget {
  const PaymentReportPage({super.key});

  @override
  State<PaymentReportPage> createState() => _PaymentReportPageState();
}

class _PaymentReportPageState extends State<PaymentReportPage> {
  static const Color _primaryColor = Color(0xff1458a3);
  static const Color _accentColor = Color(0xff2e7d32);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _filterStatus = 'All';
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;

  List<PaymentTransaction> _transactions = [];
  List<Invoice> _invoices = [];
  bool _loading = true;

  // Stats
  double _totalRevenue = 0;
  double _outstandingFees = 0;
  double _collectedThisMonth = 0;
  Map<String, double> _chartData = {};
  String _chartPeriod = 'Monthly'; // 'Daily', 'Weekly', 'Monthly'
  
  // Payment method breakdown
  int _paypalCount = 0;
  double _paypalAmount = 0;
  int _manualCount = 0;
  double _manualAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final now = TimezoneHelper.getMalaysiaTime();
      final startOfMonth =
          TimezoneHelper.createMalaysiaDateTime(now.year, now.month, 1, 0, 0);
      final endOfMonth = TimezoneHelper.createMalaysiaDateTime(
              now.year, now.month + 1, 1, 0, 0)
          .subtract(const Duration(seconds: 1));

      // Load transactions
      final txnSnapshot = await _db
          .collection('payment_transactions')
          .orderBy('createdAt', descending: true)
          .get();

      final transactions = txnSnapshot.docs
          .map((doc) => PaymentTransaction.fromMap(doc.id, doc.data()))
          .toList();

      // Load invoices
      final invSnapshot = await _db.collection('invoices').get();
      final invoices = invSnapshot.docs
          .map((doc) => Invoice.fromMap(doc.id, doc.data()))
          .toList();

      // Calculate stats
      double totalRevenue = 0;
      double outstanding = 0;
      double collectedThisMonth = 0;
      
      // Payment method breakdown
      int paypalCount = 0;
      double paypalAmount = 0;
      int manualCount = 0;
      double manualAmount = 0;

      for (var inv in invoices) {
        if (inv.status == 'paid') {
          totalRevenue += inv.totalAmount;

          // Check if paid this month
          if (inv.paidAt != null) {
            final paidAtMalaysia = TimezoneHelper.toMalaysiaTime(inv.paidAt!);
            if (!paidAtMalaysia.isBefore(startOfMonth) &&
                !paidAtMalaysia.isAfter(endOfMonth)) {
              collectedThisMonth += inv.totalAmount;
            }
          }
        } else if (inv.status == 'pending' || inv.status == 'overdue') {
          outstanding += inv.totalAmount;
        }
      }
      
      // Calculate payment method breakdown from completed transactions
      for (var txn in transactions) {
        if (txn.status == 'completed') {
          if (txn.paymentMethod == 'paypal') {
            paypalCount++;
            paypalAmount += txn.amount;
          } else if (txn.paymentMethod == 'manual' || txn.paymentMethod == 'cash') {
            manualCount++;
            manualAmount += txn.amount;
          }
        }
      }

      // Load chart data
      final chartData = _calculateChartData(transactions);

      setState(() {
        _transactions = transactions;
        _invoices = invoices;
        _totalRevenue = totalRevenue;
        _outstandingFees = outstanding;
        _collectedThisMonth = collectedThisMonth;
        _chartData = chartData;
        _paypalCount = paypalCount;
        _paypalAmount = paypalAmount;
        _manualCount = manualCount;
        _manualAmount = manualAmount;
        _loading = false;
      });
    } catch (e) {
      print('Error loading payment data: $e');
      setState(() => _loading = false);
    }
  }

  Map<String, double> _calculateChartData(List<PaymentTransaction> transactions) {
    final now = TimezoneHelper.getMalaysiaTime();
    final startOfToday =
        TimezoneHelper.createMalaysiaDateTime(now.year, now.month, now.day, 0, 0);
    Map<String, double> chartData = {};
    
    // Filter completed transactions
    final completedTxns = transactions.where((t) => t.status == 'completed').toList();

    if (_chartPeriod == 'Daily') {
      // Last 7 days (Malaysia time)
      for (int i = 6; i >= 0; i--) {
        final dayStart = startOfToday.subtract(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        final labelDate = TimezoneHelper.toMalaysiaTime(dayStart);
        final dayKey = DateFormat('EEE').format(labelDate);
        
        double dayTotal = 0;
        for (var txn in completedTxns) {
          if (txn.completedAt == null) continue;
          final completedAtMalaysia = TimezoneHelper.toMalaysiaTime(txn.completedAt!);
          if (!completedAtMalaysia.isBefore(dayStart) &&
              !completedAtMalaysia.isAfter(dayEnd)) {
            dayTotal += txn.amount;
          }
        }
        chartData[dayKey] = dayTotal;
      }
    } else if (_chartPeriod == 'Weekly') {
      // Last 4 weeks (Malaysia time)
      for (int i = 3; i >= 0; i--) {
        final weekStart = startOfToday.subtract(Duration(days: (i * 7) + 6));
        final weekEnd = startOfToday
            .subtract(Duration(days: i * 7))
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
        final weekKey = 'Wk${4 - i}';
        
        double weekTotal = 0;
        for (var txn in completedTxns) {
          if (txn.completedAt == null) continue;
          final completedAtMalaysia = TimezoneHelper.toMalaysiaTime(txn.completedAt!);
          if (!completedAtMalaysia.isBefore(weekStart) &&
              !completedAtMalaysia.isAfter(weekEnd)) {
            weekTotal += txn.amount;
          }
        }
        chartData[weekKey] = weekTotal;
      }
    } else {
      // Monthly - Last 6 months (Malaysia time)
      for (int i = 5; i >= 0; i--) {
        final monthStart =
            TimezoneHelper.createMalaysiaDateTime(now.year, now.month - i, 1, 0, 0);
        final monthEnd = TimezoneHelper.createMalaysiaDateTime(
                now.year, now.month - i + 1, 1, 0, 0)
            .subtract(const Duration(seconds: 1));
        final labelDate = TimezoneHelper.toMalaysiaTime(monthStart);
        final monthKey = DateFormat('MMM').format(labelDate);
        
        double monthTotal = 0;
        for (var txn in completedTxns) {
          if (txn.completedAt == null) continue;
          final completedAtMalaysia = TimezoneHelper.toMalaysiaTime(txn.completedAt!);
          if (!completedAtMalaysia.isBefore(monthStart) &&
              !completedAtMalaysia.isAfter(monthEnd)) {
            monthTotal += txn.amount;
          }
        }
        chartData[monthKey] = monthTotal;
      }
    }

    return chartData;
  }

  void _changeChartPeriod(String period) {
    setState(() {
      _chartPeriod = period;
      _chartData = _calculateChartData(_transactions);
    });
  }

  List<PaymentTransaction> get _filteredTransactions {
    return _transactions.where((txn) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          txn.studentName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          txn.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          txn.invoiceId.toLowerCase().contains(_searchQuery.toLowerCase());

      // Status filter
      final matchesStatus = _filterStatus == 'All' ||
          (_filterStatus == 'Paid' && txn.status == 'completed') ||
          (_filterStatus == 'Pending' && txn.status == 'pending') ||
          (_filterStatus == 'Failed' && txn.status == 'failed');

      // Date filter
      bool matchesDate = true;
      if (_selectedDateRange != null) {
        final txnDate = txn.createdAt;
        matchesDate = txnDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            txnDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2027),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accentColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final now = TimezoneHelper.toMalaysiaTime(DateTime.now());
    final filtered = _filteredTransactions;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text("Financial Report",
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
                "Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}"),
            pw.Divider(),
            pw.SizedBox(height: 20),

            // Summary
            pw.Text("Summary",
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Metric', 'Value'],
              data: [
                ['Total Revenue', 'RM ${_totalRevenue.toStringAsFixed(2)}'],
                ['Outstanding', 'RM ${_outstandingFees.toStringAsFixed(2)}'],
                [
                  'Collected (${DateFormat('MMM').format(now)})',
                  'RM ${_collectedThisMonth.toStringAsFixed(2)}'
                ],
              ],
            ),
            pw.SizedBox(height: 20),

            // Transactions
            pw.Text("Recent Transactions (${filtered.length})",
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Date', 'Name', 'Amount', 'Method', 'Status'],
              data: filtered.take(50).map((t) {
                return [
                  DateFormat('MMM d, yyyy').format(
                      TimezoneHelper.toMalaysiaTime(t.createdAt)),
                  t.studentName,
                  'RM ${t.amount.toStringAsFixed(2)}',
                  t.paymentMethod,
                  t.status,
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'financial_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _filteredTransactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Financial Overview",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date chip
                    if (_selectedDateRange != null) _buildDateChip(),

                    // Revenue Card
                    _buildRevenueCard(),
                    const SizedBox(height: 20),

                    // Stats Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildFinanceStat(
                            "Outstanding",
                            'RM ${_outstandingFees.toStringAsFixed(2)}',
                            Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFinanceStat(
                            "Collected",
                            'RM ${_collectedThisMonth.toStringAsFixed(2)}',
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Monthly Revenue Chart
                    _buildMonthlyChart(),
                    const SizedBox(height: 24),
                    
                    // Payment Method Breakdown
                    _buildPaymentMethodBreakdown(),
                    const SizedBox(height: 24),

                    // Filter & Search
                    _buildFilters(),
                    const SizedBox(height: 16),

                    // Transaction List Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${filteredList.length} Transactions',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (_filterStatus != 'All' ||
                            _searchQuery.isNotEmpty ||
                            _selectedDateRange != null)
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _filterStatus = 'All';
                                _searchQuery = '';
                                _selectedDateRange = null;
                              });
                            },
                            child: const Text('Clear filters'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Transaction List
                    if (filteredList.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          return _buildTransactionCard(filteredList[index]);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDateChip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range, color: _accentColor, size: 18),
          const SizedBox(width: 8),
          Text(
            "${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}",
            style: TextStyle(
              color: _accentColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _selectedDateRange = null),
            child: Icon(Icons.close, size: 16, color: _accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accentColor, _accentColor.withGreen(150)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Total Revenue",
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              const SizedBox(height: 8),
              Text(
                'RM ${_totalRevenue.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.trending_up,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    // Calculate max for scaling
    double maxRevenue = 1;
    for (var entry in _chartData.entries) {
      if (entry.value > maxRevenue) maxRevenue = entry.value;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Revenue Trend",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              // Period selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: ['Daily', 'Weekly', 'Monthly'].map((period) {
                    final isSelected = _chartPeriod == period;
                    return InkWell(
                      onTap: () => _changeChartPeriod(period),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? _accentColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          period,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: _chartData.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _chartData.entries.map((entry) {
                      final pct = maxRevenue > 0 ? entry.value / maxRevenue : 0.0;
                      return _buildRevenueBar(entry.key, pct.toDouble(), entry.value.toDouble());
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text("Export Financial Report"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: _accentColor),
                foregroundColor: _accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown() {
    final totalCount = _paypalCount + _manualCount;
    final paypalPct = totalCount > 0 ? (_paypalCount / totalCount * 100).round() : 0;
    final manualPct = totalCount > 0 ? (_manualCount / totalCount * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Payment Method Breakdown",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              Icon(Icons.pie_chart, color: _accentColor.withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 20),
          
          // PayPal
          _buildMethodRow(
            icon: Icons.paypal,
            label: 'Online (PayPal)',
            count: _paypalCount,
            amount: _paypalAmount,
            percentage: paypalPct,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          
          // Manual/Cash
          _buildMethodRow(
            icon: Icons.payments_outlined,
            label: 'Manual / Cash',
            count: _manualCount,
            amount: _manualAmount,
            percentage: manualPct,
            color: Colors.orange,
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          
          // Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Transactions',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              Text(
                '$totalCount',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodRow({
    required IconData icon,
    required String label,
    required int count,
    required double amount,
    required int percentage,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '$count transactions • RM ${amount.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$percentage%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueBar(String label, double pct, double value) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          value > 0 ? 'RM ${(value / 1000).toStringAsFixed(1)}k' : '0',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: _accentColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: (120 * pct).clamp(4, 120),
          width: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_accentColor.withOpacity(0.6), _accentColor],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        // Search
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or ID...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _accentColor, width: 1.5),
            ),
          ),
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
        const SizedBox(height: 12),
        // Status chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Paid', 'Pending', 'Failed'].map((status) {
              final isSelected = _filterStatus == status;
              Color chipColor;
              switch (status) {
                case 'Paid':
                  chipColor = Colors.green;
                  break;
                case 'Pending':
                  chipColor = Colors.orange;
                  break;
                case 'Failed':
                  chipColor = Colors.red;
                  break;
                default:
                  chipColor = Colors.grey;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    status,
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
                  onSelected: (_) => setState(() => _filterStatus = status),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(PaymentTransaction txn) {
    final isPaid = txn.status == 'completed';
    final isFailed = txn.status == 'failed';
    Color statusColor = isPaid
        ? Colors.green
        : isFailed
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
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
                isPaid
                    ? Icons.check_circle_outline
                    : isFailed
                        ? Icons.cancel_outlined
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
                    txn.studentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${txn.paymentMethod.toUpperCase()} • ${DateFormat('MMM d, yyyy').format(TimezoneHelper.toMalaysiaTime(txn.createdAt))}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'RM ${txn.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isPaid ? Colors.green : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    txn.status.toUpperCase(),
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
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.receipt_long, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No transactions found',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
