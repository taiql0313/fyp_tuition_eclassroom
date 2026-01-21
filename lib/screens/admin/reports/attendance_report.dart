import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AttendanceReportPage extends StatefulWidget {
  const AttendanceReportPage({super.key});

  @override
  State<AttendanceReportPage> createState() => _AttendanceReportPageState();
}

class _AttendanceReportPageState extends State<AttendanceReportPage> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _rateFilter = 'All';
  String _sortBy = 'Rate (Low)';
  DateTimeRange? _selectedDateRange;

  final List<Map<String, dynamic>> _students = [
    {'name': 'Ali Ahmad', 'id': 'S101', 'class': 'Maths Form 4', 'rate': 65},
    {'name': 'Tan Wei Ling', 'id': 'S102', 'class': 'Science Form 5', 'rate': 95},
    {'name': 'Muthu Sami', 'id': 'S103', 'class': 'Maths Form 4', 'rate': 92},
    {'name': 'Sarah Jones', 'id': 'S104', 'class': 'English Form 3', 'rate': 70},
    {'name': 'John Doe', 'id': 'S105', 'class': 'Science Form 5', 'rate': 88},
    {'name': 'Jessica Lim', 'id': 'S106', 'class': 'Maths Form 4', 'rate': 45},
  ];

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2025),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: Colors.purple.shade700, onPrimary: Colors.white, onSurface: Colors.black)), child: child!);
      },
    );
    if (picked != null) setState(() => _selectedDateRange = picked);
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
              pw.Header(level: 0, child: pw.Text("Attendance Report", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Text("Summary", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(context: context, data: <List<String>>[['Metric', 'Value'], ['Avg Attendance', '85%'], ['Low Attendance', '3 Students']]),
              pw.SizedBox(height: 20),
              pw.Text("Student List", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(context: context, headers: ['Name', 'Class', 'Rate'], data: _students.map((s) => [s['name'], s['class'], "${s['rate']}%"]).toList()),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'attendance_report.pdf');
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredList = _students.where((student) {
      final matchesSearch = student['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) || student['class'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchesRate = true;
      if (_rateFilter == 'High (>90%)') matchesRate = student['rate'] >= 90;
      if (_rateFilter == 'Low (<75%)') matchesRate = student['rate'] < 75;
      if (_rateFilter == 'Critical (<50%)') matchesRate = student['rate'] < 50;
      return matchesSearch && matchesRate;
    }).toList();

    filteredList.sort((a, b) {
      if (_sortBy == 'Rate (High)') return b['rate'].compareTo(a['rate']);
      if (_sortBy == 'Rate (Low)') return a['rate'].compareTo(b['rate']);
      return 0;
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("Attendance Analytics"), backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white, elevation: 0, actions: [IconButton(icon: const Icon(Icons.calendar_month), tooltip: "Filter by Date Range", onPressed: _pickDateRange)]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_selectedDateRange != null) Padding(padding: const EdgeInsets.only(bottom: 20), child: _buildDateChip()),

            Row(children: [Expanded(child: _statCard("Avg Attendance", "85%", Colors.green)), const SizedBox(width: 15), Expanded(child: _statCard("Low Attendance", "15%", Colors.red))]),
            const SizedBox(height: 25),

            // --- SIMPLE GRAPH (ORIGINAL STYLE) ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Weekly Attendance Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 180,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _fancyBar("Mon", 0.82),
                        _fancyBar("Tue", 0.65),
                        _fancyBar("Wed", 0.90),
                        _fancyBar("Thu", 0.75),
                        _fancyBar("Fri", 0.88),
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
                      label: const Text("Export Graph & Data to PDF"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.purple),
                        foregroundColor: Colors.purple,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // Search & List
            Row(children: [Expanded(child: TextField(controller: _searchController, onChanged: (v) => setState(() => _searchQuery = v), decoration: _inputDec("Search Name or Class...", Icons.search)))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: _dropdownFilter(_rateFilter, ['All', 'High (>90%)', 'Low (<75%)', 'Critical (<50%)'], Icons.filter_list, (v) => setState(() => _rateFilter = v!))), const SizedBox(width: 10), Expanded(child: _dropdownFilter(_sortBy, ['Rate (Low)', 'Rate (High)'], Icons.sort, (v) => setState(() => _sortBy = v!)))]),
            const SizedBox(height: 15),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final item = filteredList[index];
                final rate = item['rate'] as int;
                Color rateColor = rate < 50 ? Colors.red : (rate < 75 ? Colors.orange : Colors.green);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  color: Colors.white,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(backgroundColor: Colors.purple.shade50, child: Text(item['name'][0], style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.bold))),
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item['class'], style: TextStyle(color: Colors.grey[600])),
                    trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: rateColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: rateColor.withOpacity(0.3))), child: Text("$rate%", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: rateColor))),
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
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.date_range, color: Colors.purple, size: 20), const SizedBox(width: 8), Text("${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}", style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.bold)), const Spacer(), InkWell(onTap: () => setState(() => _selectedDateRange = null), child: Icon(Icons.close, size: 18, color: Colors.purple.shade800))]));
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: color, width: 4)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]), child: Column(children: [Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600]))]));
  }

  Widget _fancyBar(String day, double pct) {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text("${(pct * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple)), const SizedBox(height: 6), Container(height: 120 * pct, width: 16, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple.shade300, Colors.purple.shade700], begin: Alignment.bottomCenter, end: Alignment.topCenter), borderRadius: BorderRadius.circular(8))), const SizedBox(height: 8), Text(day, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))]);
  }

  InputDecoration _inputDec(String hint, IconData icon) {
    return InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.purple), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16));
  }

  Widget _dropdownFilter(String val, List<String> items, IconData icon, Function(String?) changed) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: val, isExpanded: true, icon: const Icon(Icons.filter_list, color: Colors.purple, size: 20), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(), onChanged: changed)));
  }
}