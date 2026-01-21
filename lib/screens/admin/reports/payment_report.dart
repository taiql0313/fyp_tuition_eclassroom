import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PaymentReportPage extends StatefulWidget {
  const PaymentReportPage({super.key});

  @override
  State<PaymentReportPage> createState() => _PaymentReportPageState();
}

class _PaymentReportPageState extends State<PaymentReportPage> {
  final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'All';
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;

  // Mock Transaction Data
  final List<Map<String, dynamic>> _transactions = [
    {'id': 'TXN-1001', 'name': 'Ali Ahmad', 'amount': 'RM 150', 'status': 'Paid', 'date': '24 Oct', 'description': 'Tuition Fee - Oct'},
    {'id': 'TXN-1002', 'name': 'Sarah Lee', 'amount': 'RM 150', 'status': 'Pending', 'date': '24 Oct', 'description': 'Tuition Fee - Oct'},
    {'id': 'TXN-1003', 'name': 'John Tan', 'amount': 'RM 50', 'status': 'Paid', 'date': '23 Oct', 'description': 'Science Material Fee'},
    {'id': 'TXN-1004', 'name': 'Muthu', 'amount': 'RM 150', 'status': 'Paid', 'date': '22 Oct', 'description': 'Tuition Fee - Sep (Late)'},
    {'id': 'TXN-1005', 'name': 'Jessica', 'amount': 'RM 150', 'status': 'Pending', 'date': '21 Oct', 'description': 'Tuition Fee - Oct'},
  ];

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2025),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green.shade700,
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

  // --- PDF EXPORT ---
  Future<void> _exportPdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, child: pw.Text("Financial Report", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Text("Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}"),
              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.Text("Recent Transactions", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                context: context,
                headers: ['ID', 'Name', 'Description', 'Amount', 'Status'],
                data: _transactions.map((t) => [t['id'], t['name'], t['description'], t['amount'], t['status']]).toList(),
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'financial_report.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _transactions.where((txn) {
      final matchesSearch = txn['name'].toLowerCase().contains(_searchQuery.toLowerCase()) || txn['id'].toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _filterStatus == 'All' || txn['status'] == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Financial Overview"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDateRange)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_selectedDateRange != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _buildDateChip(),
              ),

            // Revenue Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.green.shade800, Colors.green.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Total Revenue (Oct)", style: TextStyle(color: Colors.white70)), SizedBox(height: 8), Text("RM 45,230", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))]),
                  Icon(Icons.trending_up, color: Colors.white, size: 40),
                ],
              ),
            ),
            const SizedBox(height: 25),

            Row(children: [Expanded(child: _financeStat("Outstanding", "RM 4,200", Colors.red)), const SizedBox(width: 15), Expanded(child: _financeStat("Collected", "RM 41,030", Colors.blue))]),
            const SizedBox(height: 25),

            // --- SIMPLE GRADIENT GRAPH (MATCHING ATTENDANCE) ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.green.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Monthly Revenue", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Icon(Icons.bar_chart, color: Colors.green.shade300),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _selectedDateRange == null
                          ? [
                        _revenueBar("Jun", 0.5),
                        _revenueBar("Jul", 0.6),
                        _revenueBar("Aug", 0.4),
                        _revenueBar("Sep", 0.8),
                        _revenueBar("Oct", 0.95),
                      ]
                          : [
                        _revenueBar("Wk1", 0.3),
                        _revenueBar("Wk2", 0.5),
                        _revenueBar("Wk3", 0.8),
                        _revenueBar("Wk4", 0.6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Export PDF Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text("Export Financial Report"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.green),
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // Search & List
            Row(children: [Expanded(child: TextField(controller: _searchController, onChanged: (v) => setState(() => _searchQuery = v), decoration: _inputDec("Search transaction...", Icons.search))), const SizedBox(width: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _filterStatus, icon: const Icon(Icons.filter_list, color: Colors.green), items: ['All', 'Paid', 'Pending'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _filterStatus = v!))))]),
            const SizedBox(height: 20),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredList.length,
              separatorBuilder: (c, i) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = filteredList[index];
                final isPaid = item['status'] == 'Paid';
                return Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isPaid ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(isPaid ? Icons.check_circle : Icons.pending, color: isPaid ? Colors.green.shade700 : Colors.orange.shade700)),
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 4), Text(item['description'], style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)), Text("${item['id']} • ${item['date']}", style: TextStyle(fontSize: 12, color: Colors.grey[600]))]),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(item['amount'], style: TextStyle(fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.black87, fontSize: 16)), Text(item['status'], style: TextStyle(fontSize: 11, color: isPaid ? Colors.green : Colors.orange))]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.date_range, color: Colors.green, size: 20), const SizedBox(width: 8), Text("${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}", style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)), const Spacer(), InkWell(onTap: () => setState(() => _selectedDateRange = null), child: Icon(Icons.close, size: 18, color: Colors.green.shade800))]),
    );
  }

  Widget _financeStat(String label, String value, Color color) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: color, width: 4)), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 5), Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold))]));
  }

  // --- Gradient Revenue Bar ---
  Widget _revenueBar(String label, double pct) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text("${(pct * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 6),
        Container(
          height: 120 * pct,
          width: 16,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade300, Colors.green.shade700],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
      ],
    );
  }

  InputDecoration _inputDec(String hint, IconData icon) {
    return InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.green), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16));
  }
}