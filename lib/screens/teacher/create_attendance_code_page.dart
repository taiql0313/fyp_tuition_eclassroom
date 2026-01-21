import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class CreateAttendanceCodePage extends StatefulWidget {
  const CreateAttendanceCodePage({super.key});

  @override
  State<CreateAttendanceCodePage> createState() => _CreateAttendanceCodePageState();
}

class _CreateAttendanceCodePageState extends State<CreateAttendanceCodePage> {
  // Mock Data: List of classes the teacher teaches
  final List<Map<String, dynamic>> _classes = [
    {
      'id': 'c101',
      'subject': 'Mathematics',
      'className': 'Class 4A',
      'time': '10:00 AM - 12:00 PM',
      'activeCode': null, // No code generated yet
      'isGenerating': false,
    },
    {
      'id': 'c102',
      'subject': 'Additional Mathematics',
      'className': 'Class 5B',
      'time': '2:00 PM - 4:00 PM',
      'activeCode': null,
      'isGenerating': false,
    },
    {
      'id': 'c103',
      'subject': 'Physics',
      'className': 'Form 5 Science',
      'time': 'Mon, 10:00 AM',
      'activeCode': '882190', // Example of an already active session
      'isGenerating': false,
    },
  ];

  // Helper to generate random 6-digit code
  String _generateRandomCode() {
    var rng = Random();
    int code = rng.nextInt(900000) + 100000; // Ensures 6 digits (100000-999999)
    return code.toString();
  }

  void _handleGenerateCode(int index) async {
    setState(() {
      _classes[index]['isGenerating'] = true;
    });

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    setState(() {
      _classes[index]['isGenerating'] = false;
      _classes[index]['activeCode'] = _generateRandomCode();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Session started for ${_classes[index]['subject']}!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Code copied to clipboard")),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xff1458a3);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Class Attendance"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "My Classes",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              "Select a class to generate an attendance code.",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),

            // Class List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _classes.length,
              separatorBuilder: (c, i) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final classData = _classes[index];
                final hasCode = classData['activeCode'] != null;
                final isGenerating = classData['isGenerating'];

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                    border: hasCode
                        ? Border.all(color: Colors.green.withOpacity(0.5), width: 1.5)
                        : Border.all(color: Colors.transparent),
                  ),
                  child: Column(
                    children: [
                      // Header Section
                      ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        title: Text(
                          classData['subject'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(classData['className'], style: const TextStyle(color: Colors.black87)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(classData['time'], style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: hasCode ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            hasCode ? "ACTIVE" : "INACTIVE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: hasCode ? Colors.green : Colors.grey,
                            ),
                          ),
                        ),
                      ),

                      const Divider(height: 30),

                      // Action Section
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: hasCode
                            ? _buildActiveCodeView(classData['activeCode'])
                            : SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: isGenerating ? null : () => _handleGenerateCode(index),
                            icon: isGenerating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.qr_code_2, size: 18),
                            label: Text(
                              isGenerating ? "Generating..." : "Create Session Code",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget to display when a code is active
  Widget _buildActiveCodeView(String code) {
    return Column(
      children: [
        const Text(
          "STUDENT CODE",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              code,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: Color(0xff1458a3),
              ),
            ),
            const SizedBox(width: 15),
            IconButton(
              onPressed: () => _copyToClipboard(code),
              icon: const Icon(Icons.copy, color: Colors.grey),
              tooltip: "Copy Code",
            )
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          "Share this code with your students to check in.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}