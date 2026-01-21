import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'attendance_report.dart';
import 'payment_report.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  Future<void> _exportPdf(BuildContext context) async {
    final doc = pw.Document();

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
                    pw.Text("Tuition E-Classroom", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Monthly Report", style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text("Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}"),
              pw.Divider(),
              pw.SizedBox(height: 20),

              pw.Text("Executive Summary", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),

              // Summary Table
              pw.Table.fromTextArray(
                context: context,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
                headerHeight: 30,
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
                headers: <String>['Metric', 'Value'],
                data: <List<String>>[
                  ['Total Revenue (Oct)', 'RM 45,230'],
                  ['Outstanding Fees', 'RM 4,200'],
                  ['Active Students', '1,240'],
                  ['Average Attendance', '85%'],
                  ['New Registrations', '45'],
                ],
              ),

              pw.SizedBox(height: 40),
              pw.Text("System Status: Operational", style: const pw.TextStyle(fontSize: 12, color: PdfColors.green)),
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

    // Open Print/Share Dialog
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'monthly_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xff1458a3);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("System Reports"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Export Summary PDF",
            onPressed: () => _exportPdf(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Report Category",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 15),

            _buildReportCard(
              context,
              title: "Attendance Analytics",
              subtitle: "View daily rates, absentees & trends",
              icon: Icons.pie_chart,
              color: Colors.purple,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceReportPage())),
            ),
            const SizedBox(height: 15),
            _buildReportCard(
              context,
              title: "Financial Reports",
              subtitle: "Revenue, outstanding fees & transactions",
              icon: Icons.bar_chart,
              color: Colors.green,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentReportPage())),
            ),

            const SizedBox(height: 30),
            const Text("Quick Export", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: _buildExportButton(
                      context,
                      "Monthly Summary",
                      Icons.summarize,
                          () => _exportPdf(context)
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildExportButton(
                      context,
                      "User Activity",
                      Icons.people_alt,
                          () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exporting User Activity CSV...")));
                      }
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff1458a3),
        elevation: 1,
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: const BorderSide(color: Color(0xff1458a3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}