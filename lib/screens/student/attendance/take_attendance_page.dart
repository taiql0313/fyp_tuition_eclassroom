import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';

class TakeAttendancePage extends StatefulWidget {
  const TakeAttendancePage({super.key});

  @override
  State<TakeAttendancePage> createState() => _TakeAttendancePageState();
}

class _TakeAttendancePageState extends State<TakeAttendancePage> {
  final TextEditingController _codeController = TextEditingController();
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  void _submitCode() async {
    if (_codeController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid 6-digit code")),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please log in to mark attendance")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get session by code
      final session = await _attendanceService.getSessionByCode(_codeController.text);
      
      if (session == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid or expired code"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Mark attendance
      await _attendanceService.markAttendance(
        sessionId: session.id,
        studentId: user.uid,
        studentName: user.displayName ?? 'Student',
        classId: session.classId,
        className: session.className,
        subject: session.subject,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Success Dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 60),
              SizedBox(height: 10),
              Text("Attendance Marked!"),
            ],
          ),
          content: Text(
            "You have successfully checked in for:\n\n${session.subject} (${session.className})\n${session.sessionTime != null ? 'Session: ${session.sessionTime}' : ''}",
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Go back to dashboard
              },
              child: const Text("Done", style: TextStyle(fontSize: 16)),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      String errorMessage = "Failed to mark attendance";
      if (e.toString().contains('already marked')) {
        errorMessage = "You have already marked attendance for this session";
      } else if (e.toString().contains('not logged in')) {
        errorMessage = "Please log in to mark attendance";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Check-In"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              // Icon Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock,
                  size: 80,
                  color: Color(0xff1458a3),
                ),
              ),
              const SizedBox(height: 40),

              // Title & Instruction
              const Text(
                "Enter Session Code",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1458a3),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Please enter the 6-digit code provided by your teacher to mark your attendance.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 40),

              // Code Input Field
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: "", // Hide character counter
                  hintText: "000000",
                  hintStyle: TextStyle(color: Colors.grey.shade300),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xff1458a3), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1458a3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    "Verify Code",
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}