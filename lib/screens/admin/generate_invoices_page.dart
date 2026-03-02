import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class GenerateInvoicesPage extends StatefulWidget {
  const GenerateInvoicesPage({super.key});

  @override
  State<GenerateInvoicesPage> createState() => _GenerateInvoicesPageState();
}

class _GenerateInvoicesPageState extends State<GenerateInvoicesPage> {
  final PaymentService _paymentService = PaymentService();
  final UserService _userService = UserService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  DateTime _selectedMonth = DateTime.now();
  Set<String> _selectedStudentIds = {};
  bool _selectAll = false;
  bool _isGenerating = false;
  Map<String, Map<String, dynamic>> _previewData = {}; // studentId -> preview info

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    // Load preview data for all students
    final students = await _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();

    final preview = <String, Map<String, dynamic>>{};
    final monthStart = Timestamp.fromDate(DateTime(_selectedMonth.year, _selectedMonth.month, 1));
    
    // Check for existing invoices for this month
    final existingInvoices = await _db
        .collection('invoices')
        .where('month', isEqualTo: monthStart)
        .get();
    final billedClassIdsByStudent = <String, Set<String>>{};
    for (var doc in existingInvoices.docs) {
      final invoice = Invoice.fromMap(doc.id, doc.data());
      billedClassIdsByStudent.putIfAbsent(invoice.studentId, () => <String>{});
      for (var item in invoice.items) {
        billedClassIdsByStudent[invoice.studentId]!.add(item.classId);
      }
    }
    
    for (var studentDoc in students.docs) {
      final student = AppUser.fromMap(studentDoc.id, studentDoc.data());
      if (student.classIds.isEmpty) continue;

      // Calculate total amount for this student
      double totalAmount = 0.0;
      final items = <InvoiceItem>[];

      for (var classId in student.classIds) {
        final classDoc = await _db.collection('classrooms').doc(classId).get();
        if (!classDoc.exists) continue;

        final classData = classDoc.data()!;
        final subjectId = classData['subjectId'] as String?;
        if (subjectId == null) continue;

        // Get subject price
        final subjectDoc = await _db.collection('subjects').doc(subjectId).get();
        if (!subjectDoc.exists) continue;

        final subjectData = subjectDoc.data()!;
        if (subjectData['isActive'] != true) continue;

        final price = (subjectData['price'] as num?)?.toDouble() ?? 0.0;
        totalAmount += price;

        items.add(InvoiceItem(
          subjectId: subjectId,
          subjectName: subjectData['name'] ?? 'Subject',
          classId: classId,
          className: classData['className'] ?? 'Class',
          price: price,
        ));
      }

      if (items.isNotEmpty) {
        final billedClassIds = billedClassIdsByStudent[student.uid] ?? <String>{};
        final hasExistingInvoice = billedClassIds.isNotEmpty;
        final missingItems =
            items.where((item) => !billedClassIds.contains(item.classId)).toList();
        final missingAmount =
            missingItems.fold<double>(0.0, (sum, item) => sum + item.price);
        final canGenerate = missingItems.isNotEmpty;

        preview[student.uid] = {
          'studentName': student.displayName,
          'studentEmail': student.email,
          'totalAmount': canGenerate ? missingAmount : 0.0,
          'items': missingItems,
          'classCount': missingItems.length,
          'hasExistingInvoice': hasExistingInvoice,
          'canGenerate': canGenerate,
          'existingItemCount': items.length - missingItems.length,
        };
      }
    }

    setState(() {
      _previewData = preview;
      // Only select students who have new charges by default
      _selectedStudentIds =
          Set.from(preview.keys.where((id) => preview[id]?['canGenerate'] ?? false));
      final eligibleCount =
          preview.values.where((p) => p['canGenerate'] == true).length;
      _selectAll = eligibleCount > 0 && _selectedStudentIds.length == eligibleCount;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        // Only select students who have new charges
        _selectedStudentIds = Set.from(_previewData.keys.where((id) {
          return _previewData[id]?['canGenerate'] ?? false;
        }));
      } else {
        _selectedStudentIds.clear();
      }
    });
  }

  void _toggleStudent(String studentId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedStudentIds.add(studentId);
      } else {
        _selectedStudentIds.remove(studentId);
      }
      final eligibleCount =
          _previewData.values.where((p) => p['canGenerate'] == true).length;
      _selectAll = eligibleCount > 0 && _selectedStudentIds.length == eligibleCount;
    });
  }

  Future<void> _selectMonth() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, 1, 1);
    final lastDate = DateTime(now.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select Month',
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xff1458a3),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month, 1);
      });
      _loadPreview(); // Reload preview for new month
    }
  }

  Future<void> _generateInvoices() async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select at least one student"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Selected students already filtered to those with new charges

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Generate Invoices"),
        content: Text(
          "Generate invoices for ${_selectedStudentIds.length} student(s) "
          "for ${DateFormat('MMMM yyyy').format(_selectedMonth)}?\n\n"
          "This will create invoices based on their enrolled subjects.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1458a3)),
            child: const Text("Generate", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isGenerating = true);

    int successCount = 0;
    int errorCount = 0;
    final errors = <String>[];

    for (var studentId in _selectedStudentIds) {
      try {
        await _paymentService.generateMonthlyInvoice(studentId, _selectedMonth);
        successCount++;
      } catch (e) {
        errorCount++;
        final studentName = _previewData[studentId]?['studentName'] ?? 'Unknown';
        // Clean up error message - remove "Exception: " prefix if present
        String errorMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        errors.add('$studentName: $errorMsg');
        print('Error generating invoice for $studentId: $e');
      }
    }

    setState(() => _isGenerating = false);

    if (!mounted) return;

    if (errorCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully generated ${successCount} invoice(s)!"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.pop(context);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Generation Complete"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Successfully generated: $successCount invoice(s)"),
                Text("Errors: $errorCount invoice(s)"),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text("Errors:", style: TextStyle(fontWeight: FontWeight.bold)),
                  ...errors.take(5).map((e) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text("• $e", style: const TextStyle(fontSize: 12)),
                      )),
                  if (errors.length > 5)
                    Text("... and ${errors.length - 5} more", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ],
            ),
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
  }

  pw.Widget _buildInvoicePageContent(
    String studentName,
    String studentEmail,
    List<InvoiceItem> items,
    double totalAmount,
  ) {
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
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'TUITION INVOICE',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Tuition E-Classroom', style: const pw.TextStyle(fontSize: 12, color: PdfColors.white)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PREVIEW', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.yellow)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.white),
                  ),
                ],
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
                pw.Text('Bill To:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                pw.Text(studentName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                if (studentEmail.isNotEmpty)
                  pw.Text(studentEmail, style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Invoice Month:', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                pw.Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Due: ${DateFormat('dd MMM yyyy').format(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0))}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 24),

        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xffe3f2fd)),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Subject / Class', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Amount (RM)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11), textAlign: pw.TextAlign.right),
                ),
              ],
            ),
            ...items.asMap().entries.map((entry) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('${entry.key + 1}', style: const pw.TextStyle(fontSize: 11)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('${entry.value.subjectName}\n${entry.value.className}', style: const pw.TextStyle(fontSize: 11)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(entry.value.price.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 11), textAlign: pw.TextAlign.right),
                    ),
                  ],
                )),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xfff5f5f5)),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('')),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    totalAmount.toStringAsFixed(2),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 30),

        pw.Divider(),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            'Please make payment before the due date.',
            style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
          ),
        ),
      ],
    );
  }

  pw.Document _buildInvoicePdfForStudent(String studentId) {
    final preview = _previewData[studentId]!;
    final items = preview['items'] as List<InvoiceItem>;
    final totalAmount = preview['totalAmount'] as double;
    final studentName = preview['studentName'] as String;
    final studentEmail = preview['studentEmail'] as String? ?? '';

    final pdf = pw.Document();
    final content = _buildInvoicePageContent(studentName, studentEmail, items, totalAmount);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) => content,
      ),
    );
    return pdf;
  }

  Future<void> _previewInvoicePdf(String studentId) async {
    try {
      final pdf = _buildInvoicePdfForStudent(studentId);
      final bytes = await pdf.save();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error previewing invoice: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareInvoicePdf(String studentId) async {
    try {
      final preview = _previewData[studentId]!;
      final studentName = preview['studentName'] as String;
      final pdf = _buildInvoicePdfForStudent(studentId);
      final bytes = await pdf.save();

      final dir = await getTemporaryDirectory();
      final fileName = 'Invoice_${studentName.replaceAll(' ', '_')}_${DateFormat('MMyyyy').format(_selectedMonth)}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice for $studentName - ${DateFormat('MMMM yyyy').format(_selectedMonth)}',
        subject: 'Tuition Invoice',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing invoice: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _previewAllSelectedPdf() async {
    if (_selectedStudentIds.isEmpty) return;

    try {
      final combinedPdf = pw.Document();
      for (var studentId in _selectedStudentIds) {
        final preview = _previewData[studentId]!;
        final items = preview['items'] as List<InvoiceItem>;
        final totalAmount = preview['totalAmount'] as double;
        final studentName = preview['studentName'] as String;
        final studentEmail = preview['studentEmail'] as String? ?? '';

        final content = _buildInvoicePageContent(studentName, studentEmail, items, totalAmount);
        combinedPdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context ctx) => content,
          ),
        );
      }
      final bytes = await combinedPdf.save();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error previewing invoices: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareAllSelectedPdf() async {
    if (_selectedStudentIds.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Generating invoices..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();

      // Build one combined PDF with all selected students
      final combinedPdf = pw.Document();
      for (var studentId in _selectedStudentIds) {
        final preview = _previewData[studentId]!;
        final items = preview['items'] as List<InvoiceItem>;
        final totalAmount = preview['totalAmount'] as double;
        final studentName = preview['studentName'] as String;
        final studentEmail = preview['studentEmail'] as String? ?? '';

        final content = _buildInvoicePageContent(studentName, studentEmail, items, totalAmount);
        combinedPdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context ctx) => content,
          ),
        );
      }

      final bytes = await combinedPdf.save();
      final fileName = 'Invoices_${DateFormat('MMyyyy').format(_selectedMonth)}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Tuition Invoices for ${DateFormat('MMMM yyyy').format(_selectedMonth)} (${_selectedStudentIds.length} students)',
        subject: 'Tuition Invoices',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing invoices: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligibleCount =
        _previewData.values.where((p) => p['canGenerate'] == true).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Generate Invoices"),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Month Selection Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Invoice Month",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _selectMonth,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('MMMM yyyy').format(_selectedMonth),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generateInvoices,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isGenerating ? "Generating..." : "Generate Invoices"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1458a3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Summary
          if (_previewData.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${_previewData.length} student(s) found. "
                          "$eligibleCount eligible for new charges • ${_selectedStudentIds.length} selected.",
                          style: TextStyle(color: Colors.blue[900], fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedStudentIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _previewAllSelectedPdf,
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: Text("Preview All (${_selectedStudentIds.length})"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xff1458a3),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareAllSelectedPdf,
                            icon: const Icon(Icons.share, size: 18),
                            label: Text("Share All (${_selectedStudentIds.length})"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // Students List
          Expanded(
            child: _previewData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "No students with enrolled subjects found",
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _previewData.length + 1, // +1 for select all checkbox
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // Select All Checkbox
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: CheckboxListTile(
                            title: const Text(
                              "Select All Students",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            subtitle: Text("${_selectedStudentIds.length} of $eligibleCount selected"),
                            value: _selectAll,
                            onChanged: _toggleSelectAll,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        );
                      }

                      final studentId = _previewData.keys.elementAt(index - 1);
                      final preview = _previewData[studentId]!;
                      final isSelected = _selectedStudentIds.contains(studentId);
                      final hasExistingInvoice = preview['hasExistingInvoice'] as bool? ?? false;
                      final canGenerate = preview['canGenerate'] as bool? ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: hasExistingInvoice
                            ? (canGenerate ? Colors.orange.shade50 : Colors.grey.shade100)
                            : null,
                        child: ExpansionTile(
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: !canGenerate
                                ? null // Disable checkbox if invoice already exists
                                : (value) => _toggleStudent(studentId, value),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  preview['studentName'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (hasExistingInvoice)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: canGenerate ? Colors.orange : Colors.grey,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    canGenerate ? "New Class Added" : "Up To Date",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            hasExistingInvoice
                                ? (canGenerate
                                    ? "Additional charges for ${DateFormat('MMMM yyyy').format(_selectedMonth)} • ${preview['classCount']} subject(s) • RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}"
                                    : "All classes already billed for ${DateFormat('MMMM yyyy').format(_selectedMonth)}")
                                : "${preview['classCount']} subject(s) • RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}",
                            style: TextStyle(
                              color: hasExistingInvoice
                                  ? (canGenerate ? Colors.orange.shade700 : Colors.grey[600])
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            "RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: hasExistingInvoice
                                  ? (canGenerate ? Colors.orange.shade700 : Colors.grey)
                                  : const Color(0xff1458a3),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Subject Breakdown:",
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  if ((preview['items'] as List<InvoiceItem>).isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        "No new classes to bill for this month.",
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                      ),
                                    )
                                  else
                                    ...(preview['items'] as List<InvoiceItem>).map((item) => Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  "${item.subjectName} - ${item.className}",
                                                  style: const TextStyle(fontSize: 14),
                                                ),
                                              ),
                                              Text(
                                                "RM ${item.price.toStringAsFixed(2)}",
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Total:",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      Text(
                                        "RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xff1458a3),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (canGenerate) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _previewInvoicePdf(studentId),
                                            icon: const Icon(Icons.preview, size: 18),
                                            label: const Text("Preview PDF"),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xff1458a3),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _shareInvoicePdf(studentId),
                                            icon: const Icon(Icons.share, size: 18),
                                            label: const Text("Share"),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
