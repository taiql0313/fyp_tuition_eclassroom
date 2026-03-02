import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

  void _openQrScanner() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const _QrScannerPage()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _codeController.text = scannedCode;
      _submitCode();
    }
  }

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

      // Check if current time is within the allowed window
      if (!session.isWithinTimeWindow()) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        
        String errorMessage = "Attendance cannot be taken at this time.";
        if (session.allowedStartTime != null && session.allowedEndTime != null) {
          final now = TimezoneHelper.getMalaysiaTime();
          final startTime = TimezoneHelper.toMalaysiaTime(session.allowedStartTime!);
          final endTime = TimezoneHelper.toMalaysiaTime(session.allowedEndTime!);
          
          if (now.isBefore(startTime)) {
            final timeUntil = startTime.difference(now);
            errorMessage = "Attendance window hasn't started yet. Please wait ${timeUntil.inMinutes} minutes.";
          } else if (now.isAfter(endTime)) {
            errorMessage = "Attendance window has ended. The session time was ${session.sessionTime ?? 'already passed'}.";
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
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
      appBar: AppBar(
        title: const Text("Check-In"),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text("OR", style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner, size: 24),
                  label: const Text(
                    "Scan QR Code",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff1458a3),
                    side: const BorderSide(color: Color(0xff1458a3), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    autoStart: true,
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    String raw = barcode.rawValue!;
    String code = raw;
    if (raw.startsWith('ATTENDANCE:')) {
      code = raw.substring('ATTENDANCE:'.length);
    }

    if (code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code)) {
      _hasScanned = true;
      Navigator.pop(context, code);
    }
  }

  Widget _buildErrorWidget(BuildContext context, MobileScannerException error, Widget? child) {
    String message;
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      message = 'Camera permission denied.\nPlease enable camera access in your device settings.';
    } else {
      message = 'Could not start camera.\n${error.errorDetails?.message ?? ''}';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text("Go Back"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff1458a3),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan QR Code"),
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xff1458a3),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: _buildErrorWidget,
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanOverlayPainter(),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Point camera at the QR code",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _controller.toggleTorch(),
                      icon: const Icon(Icons.flash_on, color: Colors.white, size: 30),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black38,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: () => _controller.switchCamera(),
                      icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 30),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black38,
                        padding: const EdgeInsets.all(12),
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
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final borderPaint = Paint()
      ..color = const Color(0xff1458a3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final scanSize = size.width * 0.7;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2 - 40;
    final scanRect = Rect.fromLTWH(left, top, scanSize, scanSize);

    // Draw semi-transparent background with cutout
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16))),
      ),
      bgPaint,
    );

    // Draw border around scan area
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(16)),
      borderPaint,
    );

    // Draw corner accents
    const cornerLen = 30.0;
    final accentPaint = Paint()
      ..color = const Color(0xff1458a3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(left, top + 16), Offset(left, top + 16 + cornerLen), accentPaint);
    canvas.drawLine(Offset(left + 16, top), Offset(left + 16 + cornerLen, top), accentPaint);
    // Top-right
    canvas.drawLine(Offset(left + scanSize, top + 16), Offset(left + scanSize, top + 16 + cornerLen), accentPaint);
    canvas.drawLine(Offset(left + scanSize - 16, top), Offset(left + scanSize - 16 - cornerLen, top), accentPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, top + scanSize - 16), Offset(left, top + scanSize - 16 - cornerLen), accentPaint);
    canvas.drawLine(Offset(left + 16, top + scanSize), Offset(left + 16 + cornerLen, top + scanSize), accentPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + scanSize, top + scanSize - 16), Offset(left + scanSize, top + scanSize - 16 - cornerLen), accentPaint);
    canvas.drawLine(Offset(left + scanSize - 16, top + scanSize), Offset(left + scanSize - 16 - cornerLen, top + scanSize), accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}