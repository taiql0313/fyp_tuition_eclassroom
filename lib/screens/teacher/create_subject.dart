import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/subject_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/subject_model.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:intl/intl.dart';

class CreateClassroomPage extends StatefulWidget {
  const CreateClassroomPage({super.key});

  @override
  State<CreateClassroomPage> createState() => _CreateClassroomPageState();
}

class _CreateClassroomPageState extends State<CreateClassroomPage> {
  // 1. Controllers to capture the "Guild" info
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  final SubjectService _subjectService = SubjectService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _selectedSubjectId; // Store subject ID instead of name
  AppUser? _currentUser;
  bool _isLoadingUser = true;
  
  String? _selectedDay; // Day of the week
  final List<String> _daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  
  String? _selectedTimeSlot; // Class time slot
  final List<Map<String, String>> _timeSlots = [
    {'label': '8:00 AM - 10:00 AM', 'start': '08:00', 'end': '10:00'},
    {'label': '10:00 AM - 12:00 PM', 'start': '10:00', 'end': '12:00'},
    {'label': '12:00 PM - 2:00 PM', 'start': '12:00', 'end': '14:00'},
    {'label': '2:00 PM - 4:00 PM', 'start': '14:00', 'end': '16:00'},
    {'label': '4:00 PM - 6:00 PM', 'start': '16:00', 'end': '18:00'},
    {'label': '6:00 PM - 8:00 PM', 'start': '18:00', 'end': '20:00'},
    {'label': '8:00 PM - 10:00 PM', 'start': '20:00', 'end': '22:00'},
    {'label': '10:00 PM - 12:00 AM', 'start': '22:00', 'end': '00:00'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      final appUser = await _userService.getUser(user.uid);
      setState(() {
        _currentUser = appUser;
        _isLoadingUser = false;
      });
    } else {
      setState(() {
        _isLoadingUser = false;
      });
    }
  }

  bool get _isAdmin => _currentUser?.role == 'admin';

  // 2. The "Save to Firebase" function
  Future<void> _saveClassroom() async {
    // 1. Get the current logged-in teacher's info
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return; // Guard: Must be logged in

    try {
      // Validate required fields
      if (_selectedSubjectId == null || _selectedDay == null || _selectedTimeSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please fill in all required fields (Subject, Day, and Time)"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get subject details to store name and price
      final subject = await _subjectService.getSubject(_selectedSubjectId!);
      if (subject == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Selected subject not found"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 2. Add to "classrooms" collection
      await FirebaseFirestore.instance.collection('classrooms').add({
        'className': _nameController.text,
        'subject': subject.name,
        'subjectId': _selectedSubjectId,
        'subjectPrice': subject.price,
        'classCode': _codeController.text,
        'section': _sectionController.text,
        'description': _descController.text,
        
        // Day and time information
        'day': _selectedDay,
        'classTime': _selectedTimeSlot,
        'timeStart': _timeSlots.firstWhere((slot) => slot['label'] == _selectedTimeSlot)['start'],
        'timeEnd': _timeSlots.firstWhere((slot) => slot['label'] == _selectedTimeSlot)['end'],

        // CRITICAL: Link to this specific teacher
        'teacherId': user.uid,
        'teacherName': user.displayName ?? "Teacher",

        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context); // Go back after success
    } catch (e) {
      print("Error saving class: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Classroom', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOP PREVIEW CARD (Matches your pic) ---
            _buildPreviewCard(),

            const SizedBox(height: 30),
            const Text("Classroom Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // --- INPUT FIELDS ---
            _buildInputField("Classroom Name", "e.g., Data Structures 2024", Icons.book, _nameController),

            const SizedBox(height: 15),
            _buildSubjectDropdownField(),

            const SizedBox(height: 15),
            _buildDayDropdownField(),

            const SizedBox(height: 15),
            _buildTimeDropdownField(),

            const SizedBox(height: 15),
            _buildInputField("Class Code", "e.g., CS201", Icons.code, _codeController),

            const SizedBox(height: 15),
            _buildInputField("Section (Optional)", "e.g., Section A", Icons.layers, _sectionController),

            const SizedBox(height: 15),
            _buildInputField("Description (Optional)", "Describe your classroom...", Icons.description, _descController, isLong: true),

            const SizedBox(height: 30),

            // --- CREATE BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveClassroom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1458A3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("CREATE CLASSROOM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI HELPER METHODS ---

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade300, Colors.indigo.shade400]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
            child: const Text("CLASS CODE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 15),
          const Text("Classroom Name", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          StreamBuilder<List<Subject>>(
            stream: _subjectService.streamSubjects(),
            builder: (context, snapshot) {
              if (snapshot.hasData && _selectedSubjectId != null) {
                final subject = snapshot.data!.firstWhere(
                  (s) => s.id == _selectedSubjectId,
                  orElse: () => Subject(id: '', name: 'Subject', price: 0, createdAt: DateTime.now()),
                );
                return Text(subject.name, style: const TextStyle(color: Colors.white70, fontSize: 16));
              }
              return const Text("Subject", style: TextStyle(color: Colors.white70, fontSize: 16));
            },
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.school, color: Colors.white70, size: 18),
              SizedBox(width: 5), Text("Teacher", style: TextStyle(color: Colors.white70)),
              SizedBox(width: 20),
              Icon(Icons.people, color: Colors.white70, size: 18),
              SizedBox(width: 5), Text("0 Students", style: TextStyle(color: Colors.white70)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInputField(String label, String hint, IconData icon, TextEditingController controller, {bool isLong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: isLong ? 3 : 1,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Subject", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            // Only show "Add New" button for admins
            if (_isAdmin)
              TextButton.icon(
                onPressed: () => _showCreateSubjectDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add New"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1458A3),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Subject>>(
          stream: _subjectService.streamSubjects(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text("No subjects available. Click 'Add New' to create one."),
              );
            }

            final subjects = snapshot.data!;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text("Select Subject"),
                  value: _selectedSubjectId,
                  items: subjects.map((Subject subject) {
                    return DropdownMenuItem<String>(
                      value: subject.id,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(subject.name),
                          Text(
                            'RM ${NumberFormat('#,##0.00').format(subject.price)}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedSubjectId = val),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showCreateSubjectDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => _CreateSubjectDialog(
        nameController: nameController,
        priceController: priceController,
        subjectService: _subjectService,
      ),
    );
  }

  Widget _buildDayDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Day of Week", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Day"),
              value: _selectedDay,
              items: _daysOfWeek.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (val) => setState(() => _selectedDay = val),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Class Time", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Time Slot"),
              value: _selectedTimeSlot,
              items: _timeSlots.map((slot) {
                return DropdownMenuItem<String>(
                  value: slot['label'],
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(slot['label']!),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedTimeSlot = val),
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateSubjectDialog extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final SubjectService subjectService;

  const _CreateSubjectDialog({
    required this.nameController,
    required this.priceController,
    required this.subjectService,
  });

  @override
  State<_CreateSubjectDialog> createState() => _CreateSubjectDialogState();
}

class _CreateSubjectDialogState extends State<_CreateSubjectDialog> {
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
          title: const Text("Create New Subject"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: widget.nameController,
                decoration: const InputDecoration(
                  labelText: "Subject Name",
                  hintText: "e.g., Physics",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: widget.priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Price (RM)",
                  hintText: "e.g., 150.00",
                  border: OutlineInputBorder(),
                  prefixText: "RM ",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isCreating ? null : () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: _isCreating
                  ? null
                  : () async {
                      if (widget.nameController.text.trim().isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter subject name")),
                          );
                        }
                        return;
                      }

                      final price = double.tryParse(widget.priceController.text);
                      if (price == null || price < 0) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter a valid price")),
                          );
                        }
                        return;
                      }

                      setState(() => _isCreating = true);

                      try {
                        await widget.subjectService.createSubject(
                          name: widget.nameController.text.trim(),
                          price: price,
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Subject created successfully!"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => _isCreating = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Error: ${e.toString()}"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Create"),
            ),
          ],
        );
  }
}