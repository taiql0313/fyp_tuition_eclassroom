import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/announcement_service.dart';
import '../../services/notification_service.dart';

class CreateAnnouncementPage extends StatefulWidget {
  final String? classId; // Optional: for class-specific announcements
  
  const CreateAnnouncementPage({super.key, this.classId});

  @override
  State<CreateAnnouncementPage> createState() => _CreateAnnouncementPageState();
}

class _CreateAnnouncementPageState extends State<CreateAnnouncementPage> {
  final _formKey = GlobalKey<FormState>();
  final _service = AnnouncementService();
  final _notificationService = NotificationService();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  String _title = '';
  String _content = '';
  String _type = 'class';
  bool _loading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _loading = true);

    final user = context.read<AuthService>().currentUser;
    final authorName = user?.displayName ?? "Teacher";
    final teacherName = authorName; // Use same name for teacherName

    await _service.postAnnouncement(
      title: _title,
      content: _content,
      type: _type,
      authorName: authorName,
      classId: widget.classId, // Pass classId if provided
      teacherName: teacherName,
    );

    // Notify students: class-specific or all students
    final shortContent = _content.length > 80 ? '${_content.substring(0, 80)}...' : _content;
    if (widget.classId != null && widget.classId!.isNotEmpty) {
      await _notificationService.createForStudentsInClass(
        classId: widget.classId!,
        type: 'announcement',
        title: _title,
        message: shortContent,
      );
    } else {
      await _notificationService.createForAllStudents(
        type: 'announcement',
        title: _title,
        message: shortContent,
      );
    }

    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text("Announcement posted successfully!"),
          ],
        ),
        backgroundColor: const Color(0xff10b981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'exam':
        return const Color(0xffef4444);
      case 'event':
        return const Color(0xff8b5cf6);
      default:
        return const Color(0xff1458a3);
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'exam':
        return Icons.assignment_outlined;
      case 'event':
        return Icons.event_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'exam':
        return 'Exam / Deadline';
      case 'event':
        return 'Event / Holiday';
      default:
        return 'General Class Info';
    }
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xff1458a3);
    final typeColor = _getTypeColor(_type);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Create Announcement",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section with Icon
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.campaign_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Share with Your Class",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Students will be notified instantly",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            Transform.translate(
              offset: const Offset(0, -24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type Selection Cards
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _getTypeIcon(_type),
                                    color: typeColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  "Announcement Type",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xff1f2937),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _buildTypeCard('class', 'General', Icons.info_outline)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildTypeCard('exam', 'Exam', Icons.assignment_outlined)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildTypeCard('event', 'Event', Icons.event_outlined)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Title Field
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.title, color: Colors.grey[600], size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  "Title",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xff1f2937),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Keep it short and clear",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _titleController,
                              style: const TextStyle(fontSize: 15, color: Color(0xff1f2937)),
                              decoration: InputDecoration(
                                hintText: "e.g., Math Quiz Tomorrow",
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                filled: true,
                                fillColor: const Color(0xfff8f9fa),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: typeColor, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                suffixIcon: _titleController.text.isNotEmpty
                                    ? IconButton(
                                  icon: Icon(Icons.clear, size: 20, color: Colors.grey[400]),
                                  onPressed: () {
                                    _titleController.clear();
                                    setState(() {});
                                  },
                                )
                                    : null,
                              ),
                              validator: (v) => v!.isEmpty ? "Title is required" : null,
                              onSaved: (v) => _title = v!,
                              onChanged: (v) => setState(() {}),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Content Field
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.description_outlined, color: Colors.grey[600], size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  "Content",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xff1f2937),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Provide detailed information",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _contentController,
                              style: const TextStyle(fontSize: 15, color: Color(0xff1f2937), height: 1.5),
                              maxLines: 7,
                              decoration: InputDecoration(
                                hintText: "Write the details of your announcement here...\n\nExample:\nThe math quiz will cover chapters 1-3. Please prepare well!",
                                hintStyle: TextStyle(color: Colors.grey[400], height: 1.5),
                                filled: true,
                                fillColor: const Color(0xfff8f9fa),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: typeColor, width: 2),
                                ),
                                contentPadding: const EdgeInsets.all(16),
                              ),
                              validator: (v) => v!.isEmpty ? "Content is required" : null,
                              onSaved: (v) => _content = v!,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Info Box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: typeColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.notifications_active_outlined, color: typeColor, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "All students will receive a push notification",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: typeColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xffe5e7eb)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: _loading ? null : () => Navigator.pop(context),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  color: Color(0xff6b7280),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: typeColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                                  : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.send_rounded, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Post Now",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(String value, String label, IconData icon) {
    final isSelected = _type == value;
    final color = _getTypeColor(value);

    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : const Color(0xfff8f9fa),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey[500],
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[600],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}