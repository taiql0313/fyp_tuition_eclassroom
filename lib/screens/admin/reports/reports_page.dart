import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

import 'attendance_report.dart';
import 'payment_report.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const Color _primaryColor = Color(0xff1458a3);
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stats
  double _totalRevenue = 0;
  double _outstandingFees = 0;
  int _activeStudents = 0;
  int _avgAttendance = 0;
  int _newRegistrations = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);

    try {
      final now = TimezoneHelper.getMalaysiaTime();
      final startOfMonth =
          TimezoneHelper.createMalaysiaDateTime(now.year, now.month, 1, 0, 0);
      final endOfMonth = TimezoneHelper.createMalaysiaDateTime(
              now.year, now.month + 1, 1, 0, 0)
          .subtract(const Duration(seconds: 1));

      // Get all invoices (for outstanding fees)
      final invoicesSnapshot = await _db.collection('invoices').get();
      double outstanding = 0;

      for (var doc in invoicesSnapshot.docs) {
        final data = doc.data();
        final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
        final status = data['status'] as String? ?? 'pending';

        if (status == 'pending' || status == 'overdue') {
          outstanding += amount;
        }
      }

      // Get all payment transactions (for revenue, consistent with other pages)
      final txSnapshot = await _db
          .collection('payment_transactions')
          .where('status', isEqualTo: 'completed')
          .get();

      double revenue = 0;
      for (var doc in txSnapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        // All-time total revenue (no month filter)
        revenue += amount;
      }

      // Get active students count
      final studentsSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();
      final activeStudents = studentsSnapshot.docs.length;

      // Get new registrations this month
      int newRegs = 0;
      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        if (createdAt != null &&
            createdAt.isAfter(startOfMonth) &&
            createdAt.isBefore(endOfMonth)) {
          newRegs++;
        }
      }

      // Calculate average attendance
      final recordsSnapshot = await _db.collection('attendance_records').get();
      int presentCount = 0;
      int totalRecords = recordsSnapshot.docs.length;

      for (var doc in recordsSnapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'absent';
        if (status == 'present' || status == 'excused') {
          presentCount++;
        }
      }

      final avgAttendance =
          totalRecords > 0 ? ((presentCount / totalRecords) * 100).round() : 0;

      setState(() {
        _totalRevenue = revenue;
        _outstandingFees = outstanding;
        _activeStudents = activeStudents;
        _avgAttendance = avgAttendance;
        _newRegistrations = newRegs;
        _loading = false;
      });
    } catch (e) {
      print('Error loading stats: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf(BuildContext context) async {
    final doc = pw.Document();
    final now = TimezoneHelper.toMalaysiaTime(DateTime.now());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Tuition E-Classroom",
                        style: pw.TextStyle(
                            fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Monthly Report",
                        style: const pw.TextStyle(
                            fontSize: 18, color: PdfColors.grey)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                  "Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}"),
              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.Text("Executive Summary",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                context: context,
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.blue100),
                headerHeight: 30,
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
                headers: <String>['Metric', 'Value'],
                data: <List<String>>[
                  [
                    'Total Revenue (All Time)',
                    'RM ${_totalRevenue.toStringAsFixed(2)}'
                  ],
                  ['Outstanding Fees', 'RM ${_outstandingFees.toStringAsFixed(2)}'],
                  ['Active Students', '$_activeStudents'],
                  ['Average Attendance', '$_avgAttendance%'],
                  ['New Registrations', '$_newRegistrations'],
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Text("System Status: Operational",
                  style:
                      const pw.TextStyle(fontSize: 12, color: PdfColors.green)),
              pw.SizedBox(height: 10),
              pw.Footer(
                leading: pw.Text("Confidential Document"),
                trailing: pw.Text("Page 1 of 1"),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'monthly_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "System Reports",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Data",
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Export Summary PDF",
            onPressed: () => _exportPdf(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    _buildSummaryCard(),
                    const SizedBox(height: 24),

                    // Quick Stats Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Students',
                            '$_activeStudents',
                            Icons.school,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Attendance',
                            '$_avgAttendance%',
                            Icons.check_circle_outline,
                            _avgAttendance >= 80 ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'New This Month',
                            '$_newRegistrations',
                            Icons.person_add,
                            Colors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    const Text(
                      "Report Categories",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 15),

                    _buildReportCard(
                      context,
                      title: "Attendance Analytics",
                      subtitle: "View daily rates, absentees & trends",
                      icon: Icons.pie_chart,
                      color: Colors.purple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AttendanceReportPage()),
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildReportCard(
                      context,
                      title: "Financial Reports",
                      subtitle: "Revenue, outstanding fees & transactions",
                      icon: Icons.bar_chart,
                      color: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PaymentReportPage()),
                      ),
                    ),

                    const SizedBox(height: 30),
                    const Text(
                      "Quick Export",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Expanded(
                          child: _buildExportButton(
                            context,
                            "Monthly Summary",
                            Icons.summarize,
                            () => _exportPdf(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryColor, Color(0xff4a90e2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Total Revenue",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orangeAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Outstanding: RM ${_outstandingFees.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
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
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _primaryColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: _primaryColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
