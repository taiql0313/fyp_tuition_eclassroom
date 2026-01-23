import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';

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
    
    final existingInvoiceStudentIds = existingInvoices.docs
        .map((doc) => doc.data()['studentId'] as String)
        .toSet();
    
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
        final hasExistingInvoice = existingInvoiceStudentIds.contains(student.uid);
        preview[student.uid] = {
          'studentName': student.displayName,
          'studentEmail': student.email,
          'totalAmount': totalAmount,
          'items': items,
          'classCount': items.length,
          'hasExistingInvoice': hasExistingInvoice,
        };
      }
    }

    setState(() {
      _previewData = preview;
      // Only select students who don't have existing invoices by default
      _selectedStudentIds = Set.from(preview.keys.where((id) => !(preview[id]?['hasExistingInvoice'] ?? false)));
      _selectAll = _selectedStudentIds.length == preview.length && preview.isNotEmpty;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        // Only select students who don't have existing invoices
        _selectedStudentIds = Set.from(_previewData.keys.where((id) {
          return !(_previewData[id]?['hasExistingInvoice'] ?? false);
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
      _selectAll = _selectedStudentIds.length == _previewData.length;
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

    // Check if any selected students already have invoices
    final studentsWithExistingInvoices = _selectedStudentIds.where((id) {
      return _previewData[id]?['hasExistingInvoice'] ?? false;
    }).toList();

    if (studentsWithExistingInvoices.isNotEmpty) {
      final studentNames = studentsWithExistingInvoices
          .map((id) => _previewData[id]?['studentName'] ?? 'Unknown')
          .join(', ');
      final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Cannot generate: Invoice already exists for $monthName for: $studentNames",
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Generate Invoices"),
        backgroundColor: const Color(0xff1458a3),
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
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${_previewData.length} student(s) with enrolled subjects found. "
                      "${_selectedStudentIds.length} selected.",
                      style: TextStyle(color: Colors.blue[900], fontSize: 14),
                    ),
                  ),
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
                            subtitle: Text("${_selectedStudentIds.length} of ${_previewData.length} selected"),
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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: hasExistingInvoice ? Colors.orange.shade50 : null,
                        child: ExpansionTile(
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: hasExistingInvoice
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
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "Invoice Exists",
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
                                ? "Invoice already exists for ${DateFormat('MMMM yyyy').format(_selectedMonth)} • ${preview['classCount']} subject(s) • RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}"
                                : "${preview['classCount']} subject(s) • RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}",
                            style: TextStyle(
                              color: hasExistingInvoice ? Colors.orange.shade700 : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            "RM ${(preview['totalAmount'] as double).toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: hasExistingInvoice ? Colors.orange.shade700 : const Color(0xff1458a3),
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
