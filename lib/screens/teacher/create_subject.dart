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
  bool _isLoadingLocks = false;
  bool _isSaving = false;
  
  String? _selectedDay; // Day of the week
  final List<String> _daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  
  String? _selectedForm; // Form level (Form 1-5)
  final List<String> _formLevels = ['Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5'];
  
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
  
  // Store locked time slots: key = "form-day-timeStart-timeEnd", value = class name
  Map<String, String> _lockedSlots = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadLockedTimeSlots();
  }
  
  // Load all existing time slots from classrooms
  Future<void> _loadLockedTimeSlots() async {
    setState(() => _isLoadingLocks = true);
    
    try {
      final snapshot = await FirebaseFirestore.instance.collection('classrooms').get();
      
      print('DEBUG _loadLockedTimeSlots: Found ${snapshot.docs.length} classroom documents');
      
      final Map<String, String> locks = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final form = data['form'] as String?; // Form level (Form 1, Form 2, etc.)
        final day = data['day'] as String?;
        final timeStart = data['timeStart'] as String?;
        final timeEnd = data['timeEnd'] as String?;
        final className = data['className'] as String? ?? 'Unknown Class';
        
        print('DEBUG _loadLockedTimeSlots: Classroom ${doc.id} - form="$form", day="$day", timeStart="$timeStart", timeEnd="$timeEnd", className="$className"');
        
        if (form != null && day != null && timeStart != null && timeEnd != null) {
          // Key includes form level so different forms don't conflict
          final key = '$form-$day-$timeStart-$timeEnd';
          locks[key] = className;
          print('DEBUG _loadLockedTimeSlots: Added lock key="$key" by "$className"');
        } else {
          print('DEBUG _loadLockedTimeSlots: Skipped - missing form/day/time fields');
        }
      }
      
      setState(() {
        _lockedSlots = locks;
        _isLoadingLocks = false;
      });
      
      print('DEBUG _loadLockedTimeSlots: Total locked slots: ${_lockedSlots.length}');
      print('DEBUG _loadLockedTimeSlots: All keys: ${_lockedSlots.keys.toList()}');
    } catch (e) {
      print('Error loading locked slots: $e');
      setState(() => _isLoadingLocks = false);
    }
  }
  
  // Check if a time slot is locked for a specific form and day
  bool _isTimeSlotLocked(String? form, String day, String timeStart, String timeEnd) {
    if (form == null) return false; // Can't check without form
    final key = '$form-$day-$timeStart-$timeEnd';
    final isLocked = _lockedSlots.containsKey(key);
    print('DEBUG _isTimeSlotLocked: key="$key", isLocked=$isLocked');
    return isLocked;
  }
  
  // Get the class name that locked a specific slot
  String? _getLockedByClassName(String? form, String day, String timeStart, String timeEnd) {
    if (form == null) return null;
    final key = '$form-$day-$timeStart-$timeEnd';
    return _lockedSlots[key];
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
      if (_selectedSubjectId == null || _selectedForm == null || _selectedDay == null || _selectedTimeSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please fill in all required fields (Subject, Form, Day, and Time)"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get time slot details
      final selectedSlot = _timeSlots.firstWhere((slot) => slot['label'] == _selectedTimeSlot);
      final timeStart = selectedSlot['start']!;
      final timeEnd = selectedSlot['end']!;
      
      // Check for time slot conflict (within same form level)
      if (_isTimeSlotLocked(_selectedForm, _selectedDay!, timeStart, timeEnd)) {
        final lockedBy = _getLockedByClassName(_selectedForm, _selectedDay!, timeStart, timeEnd);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('This time slot is already taken by "$lockedBy" for $_selectedForm'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      
      setState(() => _isSaving = true);
      
      // Real-time conflict check (in case another teacher just created a class)
      // Only check within the same form level
      final conflictCheck = await FirebaseFirestore.instance
          .collection('classrooms')
          .get();
      
      for (var doc in conflictCheck.docs) {
        final data = doc.data();
        // Only check conflict within the same form level
        if (data['form'] == _selectedForm &&
            data['day'] == _selectedDay &&
            data['timeStart'] == timeStart &&
            data['timeEnd'] == timeEnd) {
          setState(() => _isSaving = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('This time slot was just taken by "${data['className']}" for $_selectedForm. Please select another time.'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            // Refresh locked slots
            await _loadLockedTimeSlots();
          }
          return;
        }
      }

      // Get subject details to store name and price
      final subject = await _subjectService.getSubject(_selectedSubjectId!);
      if (subject == null) {
        setState(() => _isSaving = false);
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
        
        // Form level (Form 1-5)
        'form': _selectedForm,
        
        // Day and time information
        'day': _selectedDay,
        'classTime': _selectedTimeSlot,
        'timeStart': timeStart,
        'timeEnd': timeEnd,

        // CRITICAL: Link to this specific teacher
        'teacherId': user.uid,
        'teacherName': user.displayName ?? "Teacher",

        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Classroom created successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back after success
      }
    } catch (e) {
      print("Error saving class: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
            _buildFormDropdownField(),

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
                onPressed: _isSaving ? null : _saveClassroom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1458A3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text("Creating...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      )
                    : const Text("CREATE CLASSROOM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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

  Widget _buildFormDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Form Level", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Form (Form 1-5)"),
              value: _selectedForm,
              items: _formLevels.map((String value) {
                return DropdownMenuItem(
                  value: value,
                  child: Row(
                    children: [
                      const Icon(Icons.school, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(value),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedForm = val;
                  // Reset time slot if it's now locked for the new form
                  if (_selectedTimeSlot != null && _selectedDay != null && val != null) {
                    final selectedSlot = _timeSlots.firstWhere(
                      (s) => s['label'] == _selectedTimeSlot,
                      orElse: () => {'start': '', 'end': '', 'label': ''},
                    );
                    if (_isTimeSlotLocked(val, _selectedDay!, selectedSlot['start']!, selectedSlot['end']!)) {
                      _selectedTimeSlot = null; // Reset if locked
                    }
                  }
                });
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Time slots are only locked within the same form level',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
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
              onChanged: (val) {
                setState(() {
                  _selectedDay = val;
                  // Reset time slot if it's now locked on the new day (within same form)
                  if (_selectedTimeSlot != null && val != null && _selectedForm != null) {
                    final selectedSlot = _timeSlots.firstWhere(
                      (s) => s['label'] == _selectedTimeSlot,
                      orElse: () => {'start': '', 'end': '', 'label': ''},
                    );
                    if (_isTimeSlotLocked(_selectedForm, val, selectedSlot['start']!, selectedSlot['end']!)) {
                      _selectedTimeSlot = null; // Reset if locked
                    }
                  }
                });
              },
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
        Row(
          children: [
            const Text("Class Time", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            if (_isLoadingLocks) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
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
                // Only check lock if both form and day are selected
                final isLocked = _selectedForm != null && _selectedDay != null && 
                    _isTimeSlotLocked(_selectedForm, _selectedDay!, slot['start']!, slot['end']!);
                final lockedBy = _selectedForm != null && _selectedDay != null
                    ? _getLockedByClassName(_selectedForm, _selectedDay!, slot['start']!, slot['end']!)
                    : null;
                
                return DropdownMenuItem<String>(
                  value: slot['label'],
                  enabled: !isLocked, // Disable locked slots
                  child: Row(
                    children: [
                      Icon(
                        isLocked ? Icons.lock : Icons.access_time, 
                        size: 16, 
                        color: isLocked ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slot['label']!,
                          style: TextStyle(
                            color: isLocked ? Colors.grey : Colors.black,
                            decoration: isLocked ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (isLocked && lockedBy != null)
                        Text(
                          '($lockedBy)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade300,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                print('DEBUG onChanged: val=$val, selectedForm=$_selectedForm, selectedDay=$_selectedDay');
                // Only allow selection if not locked (check form + day + time)
                if (val != null && _selectedForm != null && _selectedDay != null) {
                  final selectedSlot = _timeSlots.firstWhere((s) => s['label'] == val);
                  final isLocked = _isTimeSlotLocked(_selectedForm, _selectedDay!, selectedSlot['start']!, selectedSlot['end']!);
                  print('DEBUG onChanged: checking lock for $_selectedForm-$_selectedDay-${selectedSlot['start']}-${selectedSlot['end']} = $isLocked');
                  print('DEBUG onChanged: lockedSlots keys = ${_lockedSlots.keys.toList()}');
                  
                  if (isLocked) {
                    print('DEBUG onChanged: BLOCKED - slot is locked for $_selectedForm');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('This time slot is already taken for $_selectedForm!'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return; // Don't allow selection
                  }
                  setState(() => _selectedTimeSlot = val);
                } else if (val != null) {
                  // Form or day not selected yet, allow time selection
                  print('DEBUG onChanged: Form or day not selected, allowing time selection');
                  setState(() => _selectedTimeSlot = val);
                }
              },
            ),
          ),
        ),
        if (_selectedForm != null && _selectedDay != null && _lockedSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Locked slots are already taken by other $_selectedForm classes',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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