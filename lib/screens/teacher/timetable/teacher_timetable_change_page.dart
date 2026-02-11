import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TeacherTimetableChangePage extends StatefulWidget {
  const TeacherTimetableChangePage({super.key});

  @override
  State<TeacherTimetableChangePage> createState() => _TeacherTimetableChangePageState();
}

class _TeacherTimetableChangePageState extends State<TeacherTimetableChangePage> {
  final List<String> _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _timeSlots = [
    '09:00-11:00',
    '11:00-13:00',
    '13:00-15:00',
    '15:00-17:00',
    '17:00-19:00',
    '19:00-21:00',
  ];

  List<Map<String, dynamic>> _classrooms = [];
  String? _selectedClassId;
  Map<String, dynamic>? _selectedClassInfo;
  Map<String, dynamic>? _currentTimetable;
  bool _isLoading = false;

  int? _newDayIndex;
  String? _newTimeSlot;
  final TextEditingController _reasonController = TextEditingController();

  Stream<QuerySnapshot<Map<String, dynamic>>>? _requestsStream;

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
  }

  Future<void> _loadTeacherClasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      final classes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'classId': doc.id,
          'className': data['className'] ?? 'Unnamed Class',
          'subject': data['subject'] ?? '',
        };
      }).toList();

      setState(() {
        _classrooms = classes;
        if (classes.isNotEmpty) {
          _selectedClassId = classes.first['classId'];
          _selectedClassInfo = classes.first;
          _loadCurrentTimetable();
          _listenToRequests();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading classes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentTimetable() async {
    if (_selectedClassId == null) return;
    setState(() => _currentTimetable = null);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', isEqualTo: _selectedClassId)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final baseSchedule = data['baseSchedule'] as Map<String, dynamic>?;
        if (baseSchedule != null) {
          setState(() => _currentTimetable = baseSchedule);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading timetable: $e')),
        );
      }
    }
  }

  void _listenToRequests() {
    if (_selectedClassId == null) return;
    final classId = _selectedClassId!;
    setState(() {
      _requestsStream = FirebaseFirestore.instance
          .collection('timetable_change_requests')
          .where('classId', isEqualTo: classId)
          .orderBy('submittedAt', descending: true)
          .limit(20)
          .snapshots();
    });
  }

  Future<void> _submitRequest() async {
    if (_selectedClassId == null || _newDayIndex == null || _newTimeSlot == null || _reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }

    if (_currentTimetable != null) {
      final currentDay = _currentTimetable!['dayOfWeek'] as int?;
      final currentStart = _currentTimetable!['startTime'];
      final currentEnd = _currentTimetable!['endTime'];
      final parts = _newTimeSlot!.split('-');
      if (parts.length == 2) {
        final newStart = parts[0];
        final newEnd = parts[1];
        if (currentDay == _newDayIndex && currentStart == newStart && currentEnd == newEnd) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Requested slot matches current timetable')),
          );
          return;
        }
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final teacherDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final teacherName = teacherDoc.data()?['displayName'] ?? 'Teacher';

    final parts = _newTimeSlot!.split('-');
    final newStart = parts[0];
    final newEnd = parts[1];

    final currentDayIndex = _currentTimetable?['dayOfWeek'] as int?;
    final currentStart = _currentTimetable?['startTime'] as String?;
    final currentEnd = _currentTimetable?['endTime'] as String?;

    try {
      await FirebaseFirestore.instance.collection('timetable_change_requests').add({
        'classId': _selectedClassId,
        'className': _selectedClassInfo?['className'] ?? '',
        'subject': _selectedClassInfo?['subject'] ?? '',
        'teacherId': user.uid,
        'teacherName': teacherName,
        'currentSlot': currentDayIndex != null
            ? {
                'dayOfWeek': currentDayIndex,
                'startTime': currentStart,
                'endTime': currentEnd,
              }
            : null,
        'requestedSlot': {
          'dayOfWeek': _newDayIndex,
          'startTime': newStart,
          'endTime': newEnd,
        },
        'reason': _reasonController.text.trim(),
        'status': 'pending',
        'adminComment': '',
        'submittedAt': FieldValue.serverTimestamp(),
        'processedAt': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request submitted for approval'), backgroundColor: Colors.green),
        );
        _reasonController.clear();
        setState(() {
          _newDayIndex = null;
          _newTimeSlot = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting request: $e')),
        );
      }
    }
  }

  String _formatSlot(Map<String, dynamic>? slot) {
    if (slot == null) return 'Not scheduled';
    final dayIndex = slot['dayOfWeek'] as int? ?? 0;
    final dayName = _dayNames[dayIndex % 7];
    final startTime = slot['startTime'] ?? '--:--';
    final endTime = slot['endTime'] ?? '--:--';
    return '$dayName • $startTime - $endTime';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Modify Timetable', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1458A3),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classrooms.isEmpty
              ? const Center(child: Text('No classes assigned to you yet.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Class', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedClassId,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _classrooms.map<DropdownMenuItem<String>>((c) {
                          final classId = c['classId'] as String? ?? '';
                          return DropdownMenuItem<String>(
                            value: classId,
                            child: Text('${c['className']} (${c['subject']})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final classInfo = _classrooms.firstWhere(
                            (c) => c['classId'] == value,
                            orElse: () => {},
                          );
                          if (classInfo.isEmpty) return;
                          setState(() {
                            _selectedClassId = value;
                            _selectedClassInfo = classInfo;
                            _newDayIndex = null;
                            _newTimeSlot = null;
                          });
                          _loadCurrentTimetable();
                          _listenToRequests();
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildCurrentTimetableCard(),
                      const SizedBox(height: 16),
                      _buildChangeForm(),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _submitRequest,
                        icon: const Icon(Icons.send),
                        label: const Text('Submit Change Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1458A3),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildRequestHistory(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCurrentTimetableCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Timetable', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _currentTimetable == null ? 'No approved timetable yet' : _formatSlot(_currentTimetable),
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Requested New Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _newDayIndex,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelText: 'Day of Week',
            ),
            items: List.generate(_dayNames.length, (index) {
              return DropdownMenuItem(
                value: index,
                child: Text(_dayNames[index]),
              );
            }),
            onChanged: (value) => setState(() => _newDayIndex = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _newTimeSlot,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelText: 'Time Slot',
            ),
            items: _timeSlots.map((slot) => DropdownMenuItem(value: slot, child: Text(slot))).toList(),
            onChanged: (value) => setState(() => _newTimeSlot = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason for change',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestHistory() {
    if (_requestsStream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('No previous change requests.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data();
              final status = data['status'] as String? ?? 'pending';
              final reason = data['reason'] as String? ?? '';
              final requestedSlot = data['requestedSlot'] as Map<String, dynamic>?;
              final currentSlot = data['currentSlot'] as Map<String, dynamic>?;
              final adminComment = data['adminComment'] as String? ?? '';
              final submittedAt = (data['submittedAt'] as Timestamp?)?.toDate();

              Color statusColor;
              switch (status) {
                case 'approved':
                  statusColor = Colors.green;
                  break;
                case 'rejected':
                  statusColor = Colors.red;
                  break;
                default:
                  statusColor = Colors.orange;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Spacer(),
                        if (submittedAt != null)
                          Text(
                            '${submittedAt.toLocal()}'.split('.')[0],
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Current: ${currentSlot == null ? 'Not set' : _formatSlot(currentSlot)}'),
                    Text('Requested: ${_formatSlot(requestedSlot)}'),
                    const SizedBox(height: 8),
                    Text('Reason: $reason'),
                    if (adminComment.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Admin Comment: $adminComment'),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
