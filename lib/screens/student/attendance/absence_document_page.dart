import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AbsenceDocumentPage extends StatefulWidget {
  const AbsenceDocumentPage({super.key});

  @override
  State<AbsenceDocumentPage> createState() => _AbsenceDocumentPageState();
}

class _AbsenceDocumentPageState extends State<AbsenceDocumentPage> {
  final _dateController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isFileSelected = false; // Mock state for file selection
  String _fileName = "";
  DateTimeRange? _selectedDateRange; // Store the actual range object

  @override
  void dispose() {
    _dateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // Date Range Picker Logic
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xff1458a3), // Header background color
              onPrimary: Colors.white, // Header text color
              onSurface: Colors.black, // Body text color
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        // Format: "2023-10-01 - 2023-10-03" or just "2023-10-01" if same day
        final start = DateFormat('yyyy-MM-dd').format(picked.start);
        final end = DateFormat('yyyy-MM-dd').format(picked.end);

        if (start == end) {
          _dateController.text = start;
        } else {
          _dateController.text = "$start  to  $end";
        }
      });
    }
  }

  void _submitForm() {
    if (_dateController.text.isEmpty || _reasonController.text.isEmpty || !_isFileSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields and upload a document."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Mock Success
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Document Submitted Successfully!"),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Submit Absence Proof"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Upload Supporting Document",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              "Please upload a clear photo or PDF of your Medical Certificate (MC) or explanation letter.",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),

            // --- Enhanced File Upload Area ---
            GestureDetector(
              onTap: () {
                setState(() {
                  _isFileSelected = true;
                  _fileName = "medical_certificate.jpg"; // Mock file selection
                });
              },
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isFileSelected ? Colors.green.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isFileSelected ? Colors.green : Colors.grey.shade300,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isFileSelected ? Icons.check_circle : Icons.cloud_upload_outlined,
                      size: 50,
                      color: _isFileSelected ? Colors.green : const Color(0xff1458a3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isFileSelected ? "File Selected" : "Tap to Select File",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isFileSelected ? Colors.green : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isFileSelected ? _fileName : "Supported formats: JPG, PNG, PDF",
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (_isFileSelected)
                      TextButton(
                        onPressed: () => setState(() => _isFileSelected = false),
                        child: const Text("Remove", style: TextStyle(color: Colors.red)),
                      )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Text("Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // --- Date Range Picker Input ---
            TextFormField(
              controller: _dateController,
              readOnly: true, // Prevent manual typing
              onTap: () => _selectDateRange(context),
              decoration: _inputDecoration("Date Range of Absence", Icons.date_range),
            ),
            const SizedBox(height: 16),

            // --- Reason Input ---
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              decoration: _inputDecoration("Reason / Remarks", Icons.edit_note).copyWith(
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 40),

            // --- Submit Button ---
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1458a3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: _submitForm,
                child: const Text(
                  "Submit Document",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for consistent input styling
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xff1458a3)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff1458a3), width: 2),
      ),
    );
  }
}