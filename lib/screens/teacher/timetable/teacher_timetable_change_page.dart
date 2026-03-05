import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherTimetableChangePage extends StatefulWidget {
  const TeacherTimetableChangePage({super.key});

  @override
  State<TeacherTimetableChangePage> createState() =>
      _TeacherTimetableChangePageState();
}

class _TeacherTimetableChangePageState
    extends State<TeacherTimetableChangePage> with WidgetsBindingObserver {
  final List<String> _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

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

  List<Map<String, dynamic>> _classrooms = [];
  String? _selectedClassId;
  Map<String, dynamic>? _selectedClassInfo;
  Map<String, dynamic>? _currentTimetable;
  List<dynamic> _cancelledDatesList = []; // Dates already cancelled (for filter)
  String? _timetableDocId; // For updating cancelledDates
  bool _isLoading = false;
  bool _isSaving = false;

  DateTime? _selectedDate; // The specific session date to replace (selected from dropdown)
  String? _selectedReplacementDay; // Day of week for replacement (e.g. "Monday")
  DateTime? _customReplacementDate; // Explicit date for replacement (when user picks specific date)
  String? _selectedTimeSlotLabel;
  final TextEditingController _reasonController = TextEditingController();

  // Cancel class section
  DateTime? _cancelSessionDate; // Date to cancel (e.g. holiday)
  final TextEditingController _cancelReasonController = TextEditingController();
  bool _isCancelling = false;

  // Permanent timetable change (requires admin approval)
  String? _permChangeDay; // Requested day (e.g. "Tuesday")
  String? _permChangeTimeSlotLabel;
  final TextEditingController _permChangeReasonController = TextEditingController();
  bool _isSubmittingPermChange = false;

  /// Map day name to Dart weekday (Monday=1 ... Sunday=7)
  int _dayNameToWeekday(String dayName) {
    const map = {
      'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
      'Friday': 5, 'Saturday': 6, 'Sunday': 7,
    };
    return map[dayName] ?? 1;
  }

  /// Get list of upcoming dates when the class normally meets (based on original schedule)
  List<DateTime> _getUpcomingSessionDates() {
    String? dayName;
    // Prefer timetable collection data (always fresh from _loadCurrentTimetable)
    final dayOfWeek = _currentTimetable?['dayOfWeek'] as int?;
    if (dayOfWeek != null && dayOfWeek >= 0 && dayOfWeek <= 6) {
      const adminDays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      dayName = adminDays[dayOfWeek];
    }
    // Fallback: use classroom info
    if (dayName == null || dayName.isEmpty) {
      dayName = _selectedClassInfo?['day'] as String?;
    }
    if (dayName == null || dayName.isEmpty) return [];

    final targetWeekday = _dayNameToWeekday(dayName);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<DateTime> dates = [];

    // Generate next 4 months of matching dates
    for (int i = 0; i < 120; i++) {
      final d = today.add(Duration(days: i));
      if (d.weekday == targetWeekday) {
        dates.add(d);
        if (dates.length >= 20) break; // Cap at 20 sessions
      }
    }
    return dates;
  }

  /// Compute replacement date: use custom date if set, else same-week day
  DateTime? _getReplacementDateFromSelection() {
    if (_customReplacementDate != null) return _customReplacementDate;
    if (_selectedDate == null || _selectedReplacementDay == null) return null;
    final targetWeekday = _dayNameToWeekday(_selectedReplacementDay!);
    final originalDate = _selectedDate!;
    final daysFromMonday = originalDate.weekday - 1;
    final mondayOfWeek = originalDate.subtract(Duration(days: daysFromMonday));
    return mondayOfWeek.add(Duration(days: targetWeekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTeacherClasses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reasonController.dispose();
    _cancelReasonController.dispose();
    _permChangeReasonController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentClassData();
    }
  }

  Future<void> _refreshCurrentClassData() async {
    if (_selectedClassId == null) return;
    
    try {
      // Reload the classroom data to get updated schedule
      final classDoc = await FirebaseFirestore.instance
          .collection('classrooms')
          .doc(_selectedClassId)
          .get();
      
      if (classDoc.exists && mounted) {
        final data = classDoc.data()!;
        final updatedClassInfo = {
          'classId': classDoc.id,
          'className': data['className'] ?? 'Unnamed Class',
          'subject': data['subject'] ?? '',
          'day': data['day'] ?? '',
          'timeStart': data['timeStart'] ?? '',
          'timeEnd': data['timeEnd'] ?? '',
          'classTime': data['classTime'] ?? '',
          'form': data['form'] ?? '',
        };
        
        setState(() {
          _selectedClassInfo = updatedClassInfo;
          // Update in the list too
          final index = _classrooms.indexWhere((c) => c['classId'] == _selectedClassId);
          if (index != -1) {
            _classrooms[index] = updatedClassInfo;
          }
        });
        
        // Also reload timetable
        await _loadCurrentTimetable();
      }
    } catch (e) {
      print('Error refreshing class data: $e');
    }
  }

  /// Admin/timetable uses 0=Sunday, 1=Monday, ..., 6=Saturday
  int _dayNameToAdminWeekday(String dayName) {
    const map = {
      'Sunday': 0, 'Monday': 1, 'Tuesday': 2, 'Wednesday': 3,
      'Thursday': 4, 'Friday': 5, 'Saturday': 6,
    };
    return map[dayName] ?? 1;
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
          'day': data['day'] ?? '',
          'timeStart': data['timeStart'] ?? '',
          'timeEnd': data['timeEnd'] ?? '',
          'classTime': data['classTime'] ?? '',
          'form': data['form'] ?? '',
        };
      }).toList();

      setState(() {
        _classrooms = classes;
        if (classes.isNotEmpty) {
          _selectedClassId = classes.first['classId'];
          _selectedClassInfo = classes.first;
          _loadCurrentTimetable();
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
    setState(() {
      _currentTimetable = null;
      _cancelledDatesList = [];
      _timetableDocId = null;
    });
    try {
      // Also refresh classroom data so _selectedClassInfo stays in sync
      final classDoc = await FirebaseFirestore.instance
          .collection('classrooms')
          .doc(_selectedClassId)
          .get();
      if (classDoc.exists && mounted) {
        final cData = classDoc.data()!;
        final updatedInfo = {
          'classId': classDoc.id,
          'className': cData['className'] ?? 'Unnamed Class',
          'subject': cData['subject'] ?? '',
          'day': cData['day'] ?? '',
          'timeStart': cData['timeStart'] ?? '',
          'timeEnd': cData['timeEnd'] ?? '',
          'classTime': cData['classTime'] ?? '',
          'form': cData['form'] ?? '',
        };
        setState(() {
          _selectedClassInfo = updatedInfo;
          final idx = _classrooms.indexWhere((c) => c['classId'] == _selectedClassId);
          if (idx != -1) _classrooms[idx] = updatedInfo;
        });
      }

      // First try to load from timetables collection
      final snapshot = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', isEqualTo: _selectedClassId)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        final baseSchedule = data['baseSchedule'] as Map<String, dynamic>?;
        final cancelledDates = data['cancelledDates'] as List<dynamic>? ?? [];
        if (baseSchedule != null) {
          setState(() {
            _currentTimetable = baseSchedule;
            _cancelledDatesList = cancelledDates;
            _timetableDocId = doc.id;
          });
          return;
        }
      }
      
      // Fallback: load from classroom document if timetable not found
      if (_selectedClassInfo != null) {
        final day = _selectedClassInfo!['day'] as String?;
        final timeStart = _selectedClassInfo!['timeStart'] as String?;
        final timeEnd = _selectedClassInfo!['timeEnd'] as String?;
        
        if (day != null && day.isNotEmpty && timeStart != null && timeEnd != null) {
          final dayOfWeek = _dayNameToAdminWeekday(day);
          setState(() {
            _currentTimetable = {
              'dayOfWeek': dayOfWeek,
              'startTime': timeStart,
              'endTime': timeEnd,
            };
          });
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

  Future<void> _submitReplacementClass() async {
    // Validation
    if (_selectedClassId == null) {
      _showError('Please select a class');
      return;
    }
    if (_selectedDate == null) {
      _showError('Please select which session to replace');
      return;
    }
    final replacementDate = _getReplacementDateFromSelection();
    if (replacementDate == null) {
      _showError('Please select replacement day or pick a specific date');
      return;
    }
    if (_selectedTimeSlotLabel == null) {
      _showError('Please select the replacement time slot');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _showError('Please provide a reason for the replacement class');
      return;
    }

    // Don't allow past dates for replacement
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final replDateOnly = DateTime(
        replacementDate!.year, replacementDate.month, replacementDate.day);
    if (replDateOnly.isBefore(todayOnly)) {
      _showError('Replacement date cannot be in the past');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      // Get time slot details
      final selectedSlot = _timeSlots.firstWhere(
        (slot) => slot['label'] == _selectedTimeSlotLabel,
      );
      final timeStart = selectedSlot['start']!;
      final timeEnd = selectedSlot['end']!;
      final timeSlotStr = '$timeStart-$timeEnd';

      final dateStr = DateFormat('yyyy-MM-dd').format(replacementDate);

      // Check if time slot is already locked for this date
      final lockDocRef = FirebaseFirestore.instance
          .collection('timeLocks')
          .doc('$dateStr-$timeSlotStr');
      final lockDoc = await lockDocRef.get();

      if (lockDoc.exists) {
        final currentLocks =
            lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
        if (currentLocks.isNotEmpty) {
          // Check if it's locked by a different teacher's class
          final lockedByOther = currentLocks.any((lock) {
            final lockMap = lock as Map<String, dynamic>;
            return lockMap['teacherId'] != user.uid;
          });
          if (lockedByOther) {
            setState(() => _isSaving = false);
            _showError(
                'This time slot is already taken on ${DateFormat('EEEE, MMM d').format(replacementDate)}');
            return;
          }
        }
      }

      // Get teacher name
      final teacherDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final teacherName =
          teacherDoc.data()?['displayName'] ?? user.displayName ?? 'Teacher';

      // Cancel any existing replacement requests for the same original date & class
      final originalDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final existingReplacements = await FirebaseFirestore.instance
          .collection('replacement_classes')
          .where('classId', isEqualTo: _selectedClassId)
          .where('teacherId', isEqualTo: user.uid)
          .where('originalDateStr', isEqualTo: originalDateStr)
          .get();

      for (var oldDoc in existingReplacements.docs) {
        final oldData = oldDoc.data();
        final oldStatus = oldData['status'] as String? ?? '';
        // Only remove pending or approved ones (not already rejected)
        if (oldStatus == 'pending' || oldStatus == 'approved') {
          // Clean up old time lock
          final oldReplDateStr = oldData['replacementDateStr'] as String? ?? '';
          final oldStart = oldData['startTime'] as String? ?? '';
          final oldEnd = oldData['endTime'] as String? ?? '';
          if (oldReplDateStr.isNotEmpty && oldStart.isNotEmpty && oldEnd.isNotEmpty) {
            final oldLockRef = FirebaseFirestore.instance
                .collection('timeLocks')
                .doc('$oldReplDateStr-$oldStart-$oldEnd');
            final oldLockDoc = await oldLockRef.get();
            if (oldLockDoc.exists) {
              final lockedBy = List<Map<String, dynamic>>.from(
                (oldLockDoc.data()?['lockedBy'] as List<dynamic>? ?? [])
                    .whereType<Map<String, dynamic>>(),
              );
              lockedBy.removeWhere((lock) => lock['timetableId'] == oldDoc.id);
              if (lockedBy.isEmpty) {
                await oldLockRef.delete();
              } else {
                await oldLockRef.update({'lockedBy': lockedBy});
              }
            }
          }
          await oldDoc.reference.delete();
        }
      }

      // Save replacement class request (requires admin approval)
      final replacementRef = await FirebaseFirestore.instance
          .collection('replacement_classes')
          .add({
        'classId': _selectedClassId,
        'className': _selectedClassInfo?['className'] ?? '',
        'subject': _selectedClassInfo?['subject'] ?? '',
        'form': _selectedClassInfo?['form'] ?? '',
        'teacherId': user.uid,
        'teacherName': teacherName,
        'originalSchedule': _currentTimetable != null
            ? {
                'dayOfWeek': _currentTimetable!['dayOfWeek'],
                'startTime': _currentTimetable!['startTime'],
                'endTime': _currentTimetable!['endTime'],
              }
            : null,
        // Original session date being replaced
        'originalDate': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
        'originalDateStr': _selectedDate != null
            ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
            : null,
        // Requested replacement date/time
        'replacementDate': Timestamp.fromDate(replacementDate),
        'replacementDateStr': dateStr,
        'startTime': timeStart,
        'endTime': timeEnd,
        'timeSlotLabel': _selectedTimeSlotLabel,
        'reason': _reasonController.text.trim(),
        'status': 'pending',
        'isOneTime': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Lock the time slot for this specific date
      final newLock = {
        'classId': _selectedClassId,
        'teacherId': user.uid,
        'subjectName': _selectedClassInfo?['className'] ?? '',
        'timetableId': replacementRef.id,
        'isReplacement': true,
      };

      if (lockDoc.exists) {
        final currentLocks =
            lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
        final exists = currentLocks
            .any((lock) => lock['classId'] == _selectedClassId);
        if (!exists) {
          currentLocks.add(newLock);
          await lockDocRef.update({'lockedBy': currentLocks});
        }
      } else {
        await lockDocRef.set({
          'date': dateStr,
          'timeSlot': timeSlotStr,
          'lockedBy': [newLock],
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Replacement request submitted for ${DateFormat('EEEE, MMM d').format(replacementDate)} ($_selectedTimeSlotLabel). Awaiting admin approval.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        // Reset form
        _reasonController.clear();
        setState(() {
          _selectedDate = null;
          _selectedReplacementDay = null;
          _customReplacementDate = null;
          _selectedTimeSlotLabel = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating replacement class: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _submitPermanentChangeRequest() async {
    if (_selectedClassId == null || _selectedClassInfo == null || _currentTimetable == null) {
      _showError('Please select a class with an existing timetable');
      return;
    }
    if (_permChangeDay == null || _permChangeTimeSlotLabel == null) {
      _showError('Please select the new day and time slot');
      return;
    }
    final reason = _permChangeReasonController.text.trim();
    if (reason.isEmpty) {
      _showError('Please provide a reason for the change');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmittingPermChange = true);
    try {
      final slot = _timeSlots.firstWhere(
        (s) => s['label'] == _permChangeTimeSlotLabel,
        orElse: () => {'start': '08:00', 'end': '10:00'},
      );
      final startTime = slot['start'] as String? ?? '08:00';
      final endTime = slot['end'] as String? ?? '10:00';

      final currentSlot = {
        'dayOfWeek': _normalizeDayOfWeekForAdmin(_currentTimetable!['dayOfWeek'] as int?),
        'startTime': _currentTimetable!['startTime'] ?? '',
        'endTime': _currentTimetable!['endTime'] ?? '',
      };
      final requestedSlot = {
        'dayOfWeek': _dayNameToAdminWeekday(_permChangeDay!),
        'startTime': startTime,
        'endTime': endTime,
      };

      final teacherDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final teacherName = teacherDoc.data()?['displayName'] ?? user.displayName ?? 'Teacher';

      await FirebaseFirestore.instance.collection('timetable_change_requests').add({
        'classId': _selectedClassId,
        'className': _selectedClassInfo!['className'] ?? '',
        'subject': _selectedClassInfo!['subject'] ?? '',
        'teacherId': user.uid,
        'teacherName': teacherName,
        'currentSlot': currentSlot,
        'requestedSlot': requestedSlot,
        'reason': reason,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Change request submitted. Awaiting admin approval.'),
            backgroundColor: Colors.green,
          ),
        );
        _permChangeReasonController.clear();
        setState(() {
          _permChangeDay = null;
          _permChangeTimeSlotLabel = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingPermChange = false);
    }
  }

  /// baseSchedule may use 1-7 (Mon=1) or 0-6 (Sun=0). Admin expects 0-6.
  int _normalizeDayOfWeekForAdmin(int? dayOfWeek) {
    if (dayOfWeek == null) return 1;
    if (dayOfWeek >= 0 && dayOfWeek <= 6) return dayOfWeek;
    return dayOfWeek == 7 ? 0 : dayOfWeek;
  }

  String _formatSchedule(Map<String, dynamic>? schedule) {
    if (schedule == null) return 'Not scheduled';
    final dayIndex = schedule['dayOfWeek'] as int? ?? 0;
    final dayName = dayIndex >= 1 && dayIndex <= 7
        ? _dayNames[dayIndex - 1]
        : _dayNames[dayIndex % 7];
    final startTime = schedule['startTime'] ?? '--:--';
    final endTime = schedule['endTime'] ?? '--:--';
    return '$dayName, $startTime - $endTime';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Modify Timetable',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1458A3),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh',
              onPressed: () async {
                await _loadTeacherClasses();
                if (_selectedClassId != null) {
                  await _refreshCurrentClassData();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Data refreshed'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Modify Timetable'),
              Tab(text: 'Permanent Change'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _classrooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.class_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text('No classes assigned to you yet.',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [
                      _buildClassworkTab(),
                      _buildPermanentChangeTab(),
                    ],
                  ),
      ),
    );
  }

  /// Classwork tab: replacement class + cancel class (no permanent change)
  Widget _buildClassworkTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('', 'Select Class'),
          const SizedBox(height: 8),
          _buildClassSelector(),
          const SizedBox(height: 16),
          _buildCurrentTimetableCard(),
          const SizedBox(height: 24),
          _buildReplacementClassSection(),
          const SizedBox(height: 24),
          _buildCancelClassSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Permanent Change tab: only the permanent timetable change form
  Widget _buildPermanentChangeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('', 'Select Class'),
          const SizedBox(height: 8),
          _buildClassSelector(),
          const SizedBox(height: 16),
          _buildCurrentTimetableCard(),
          const SizedBox(height: 24),
          _buildPermanentChangeSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildReplacementClassSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('1', 'Schedule Replacement Class (one-time)'),
        const SizedBox(height: 8),
        _buildSessionToReplaceDropdown(),
        const SizedBox(height: 16),
        _buildTimeSlotSelector(),
        const SizedBox(height: 16),
        _buildReasonField(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _submitReplacementClass,
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSaving ? 'Scheduling...' : 'Schedule Replacement Class'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1458A3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermanentChangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('2', 'Permanent Timetable Change'),
        const SizedBox(height: 8),
        const SizedBox(height: 16),
        if (_currentTimetable == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 24),
                const SizedBox(width: 12),
                const Expanded(child: Text('No timetable set for this class yet.', style: TextStyle(fontSize: 14))),
              ],
            ),
          )
        else ...[
          const Text('Request new day & time', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _permChangeDay,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              hintText: 'Select day',
            ),
            items: _dayNames.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => _permChangeDay = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeSlots.map((slot) {
              final isSelected = _permChangeTimeSlotLabel == slot['label'];
              return ChoiceChip(
                label: Text(slot['label']!, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                selected: isSelected,
                onSelected: (s) => setState(() => _permChangeTimeSlotLabel = s == true ? slot['label'] : null),
                selectedColor: const Color(0xFF1458A3),
                backgroundColor: Colors.grey.shade100,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _permChangeReasonController,
            decoration: const InputDecoration(
              labelText: 'Reason for change',
              hintText: 'e.g. Conflict with another class',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSubmittingPermChange ? null : _submitPermanentChangeRequest,
              icon: _isSubmittingPermChange
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_isSubmittingPermChange ? 'Submitting...' : 'Submit for Approval'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1458A3),
                side: const BorderSide(color: Color(0xFF1458A3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String number, String title) {
    return Row(
      children: [
        if (number.isNotEmpty)
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF1458A3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ),
        if (number.isNotEmpty) const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildClassSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedClassId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: _classrooms.map<DropdownMenuItem<String>>((c) {
            final classId = c['classId'] as String? ?? '';
            return DropdownMenuItem<String>(
              value: classId,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.class_outlined,
                        color: Color(0xFF1458A3), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${c['className']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${c['subject']} - ${c['form']}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
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
              _selectedDate = null;
              _selectedReplacementDay = null;
              _customReplacementDate = null;
              _selectedTimeSlotLabel = null;
              _cancelSessionDate = null;
              _permChangeDay = null;
              _permChangeTimeSlotLabel = null;
            });
            _loadCurrentTimetable();
          },
        ),
      ),
    );
  }

  Widget _buildCurrentTimetableCard() {
    String scheduleText;
    if (_currentTimetable != null) {
      scheduleText = 'Every ${_formatSchedule(_currentTimetable)}';
    } else {
      final classInfo = _selectedClassInfo;
      final regularDay = classInfo?['day'] ?? '';
      final regularTime = classInfo?['classTime'] ?? '';
      if (regularDay.isNotEmpty && regularTime.isNotEmpty) {
        scheduleText = 'Every $regularDay, $regularTime';
      } else {
        scheduleText = 'No regular schedule set';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.schedule, color: Color(0xFF388E3C), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Regular Schedule',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF388E3C))),
                const SizedBox(height: 4),
                Text(
                  scheduleText,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionToReplaceDropdown() {
    final upcomingDates = _getUpcomingSessionDates();
    String originalScheduleText = '';
    if (_currentTimetable != null) {
      originalScheduleText = 'Every ${_formatSchedule(_currentTimetable)}';
    } else {
      final classInfo = _selectedClassInfo;
      final day = classInfo?['day'] as String? ?? '';
      final time = classInfo?['classTime'] as String? ?? '';
      if (day.isNotEmpty && time.isNotEmpty) {
        originalScheduleText = 'Every $day, $time';
      }
    }

    if (upcomingDates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.amber.shade800, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This class has no regular schedule set, or no upcoming sessions. Please set a schedule first.',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedDate != null
              ? const Color(0xFF1458A3)
              : Colors.grey.shade300,
          width: _selectedDate != null ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1458A3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_repeat,
                  color: Color(0xFF1458A3),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      originalScheduleText.isNotEmpty
                          ? 'Original: $originalScheduleText'
                          : 'Original schedule',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Which session do you want to replace?',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DateTime>(
            value: _selectedDate,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              hintText: 'Select a date',
            ),
            items: upcomingDates.map((date) {
              return DropdownMenuItem<DateTime>(
                value: date,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1458A3)),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('EEEE, MMM d, yyyy').format(date),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedDate = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select the replacement date and time',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          // Option 1: Same week - day of week
          const Text('Option A: Same week', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _customReplacementDate == null ? _selectedReplacementDay : null,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              hintText: 'Select day (same week as original)',
            ),
            items: _dayNames.map((day) => DropdownMenuItem<String>(
              value: day,
              child: Text(day, style: const TextStyle(fontWeight: FontWeight.w500)),
            )).toList(),
            onChanged: (value) => setState(() {
              _selectedReplacementDay = value;
              _customReplacementDate = null; // Clear custom date when using day
            }),
          ),
          const SizedBox(height: 16),
          // Option 2: Pick specific date
          const Text('Option B: Pick specific date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _customReplacementDate ?? _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null && mounted) {
                setState(() {
                  _customReplacementDate = picked;
                  _selectedReplacementDay = null; // Clear day when using custom date
                });
              }
            },
            icon: const Icon(Icons.calendar_month, size: 20),
            label: Text(
              _customReplacementDate != null
                  ? DateFormat('EEEE, MMM d, yyyy').format(_customReplacementDate!)
                  : 'Choose date',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              side: BorderSide(color: _customReplacementDate != null ? const Color(0xFF1458A3) : Colors.grey.shade400),
            ),
          ),
          if (_customReplacementDate != null)
            TextButton(
              onPressed: () => setState(() => _customReplacementDate = null),
              child: Text('Clear date', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
          if (_getReplacementDateFromSelection() != null) ...[
            const SizedBox(height: 8),
            Text(
              'Replacement will be on ${DateFormat('EEE, MMM d, yyyy').format(_getReplacementDateFromSelection()!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeSlots.map((slot) {
              final isSelected = _selectedTimeSlotLabel == slot['label'];
              return ChoiceChip(
                label: Text(
                  slot['label']!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedTimeSlotLabel =
                        selected ? slot['label'] : null;
                  });
                },
                selectedColor: const Color(0xFF1458A3),
                backgroundColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color:
                        isSelected ? const Color(0xFF1458A3) : Colors.grey.shade300,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: _reasonController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Reason for replacement class',
          hintText:
              'e.g., Making up for cancelled class on Feb 10, public holiday, etc.',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 48),
            child: Icon(Icons.notes),
          ),
        ),
      ),
    );
  }

  /// Get upcoming session dates that are NOT yet cancelled
  List<DateTime> _getCancellableSessionDates() {
    final all = _getUpcomingSessionDates();
    final cancelledDateStrs = _cancelledDatesList
        .map((c) => c is Map ? c['date'] as String? : null)
        .whereType<String>()
        .toSet();
    return all.where((d) {
      final s = DateFormat('yyyy-MM-dd').format(d);
      return !cancelledDateStrs.contains(s);
    }).toList();
  }

  Widget _buildCancelClassSection() {
    final cancellableDates = _getCancellableSessionDates();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event_busy, color: Colors.orange.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cancel Class Session',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('e.g. Public holidays, school closure',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_selectedClassId == null || _timetableDocId == null)
            Text('Select a class above first.',
                style: TextStyle(color: Colors.grey.shade600))
          else if (cancellableDates.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade800, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No upcoming sessions to cancel, or all sessions in the next 4 months are already cancelled.',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 14),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const Text('Select date to cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<DateTime>(
              value: _cancelSessionDate,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                hintText: 'Choose session date',
              ),
              items: cancellableDates.map((date) {
                return DropdownMenuItem<DateTime>(
                  value: date,
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('EEEE, MMM d, yyyy').format(date),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) => setState(() => _cancelSessionDate = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cancelReasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Public holiday, school closure',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCancelling ? null : _submitCancelClass,
                icon: _isCancelling
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cancel_outlined),
                label: Text(_isCancelling ? 'Cancelling...' : 'Cancel this session'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitCancelClass() async {
    if (_selectedClassId == null || _timetableDocId == null || _cancelSessionDate == null) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_cancelSessionDate!);
    final reason = _cancelReasonController.text.trim();
    final entry = <String, dynamic>{'date': dateStr};
    if (reason.isNotEmpty) entry['reason'] = reason;

    setState(() => _isCancelling = true);
    try {
      await FirebaseFirestore.instance
          .collection('timetables')
          .doc(_timetableDocId)
          .update({
        'cancelledDates': FieldValue.arrayUnion([entry]),
        'lastModified': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session on ${DateFormat('EEEE, MMM d').format(_cancelSessionDate!)} cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _cancelSessionDate = null;
          _cancelReasonController.clear();
          _cancelledDatesList = [..._cancelledDatesList, entry];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Widget _buildReplacementHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedClassId == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 20, color: Color(0xFF1458A3)),
            const SizedBox(width: 8),
            const Text('Replacement Class History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('replacement_classes')
              .where('classId', isEqualTo: _selectedClassId)
              .where('teacherId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ));
            }

            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Error loading history: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.event_available,
                          size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('No replacement classes scheduled yet',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildHistoryCard(doc.id, data);
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHistoryCard(String docId, Map<String, dynamic> data) {
    final replacementDate =
        (data['replacementDate'] as Timestamp?)?.toDate();
    final timeLabel = data['timeSlotLabel'] as String? ?? '';
    final reason = data['reason'] as String? ?? '';
    final status = data['status'] as String? ?? 'approved';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final isPast = replacementDate != null &&
        replacementDate.isBefore(DateTime.now().subtract(const Duration(days: 1)));

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = isPast ? Colors.grey : Colors.green;
        statusIcon = isPast ? Icons.check_circle : Icons.check_circle_outline;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPast ? Colors.grey.shade200 : statusColor.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPast ? 'COMPLETED' : status.toUpperCase(),
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
              const Spacer(),
              if (createdAt != null)
                Text(
                  DateFormat('MMM d, yyyy').format(createdAt),
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 16, color: Color(0xFF1458A3)),
              const SizedBox(width: 8),
              Text(
                replacementDate != null
                    ? DateFormat('EEEE, MMMM d, yyyy')
                        .format(replacementDate)
                    : 'Date not set',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time,
                  size: 16, color: Color(0xFF1458A3)),
              const SizedBox(width: 8),
              Text(timeLabel, style: const TextStyle(fontSize: 14)),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(reason,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700)),
                ),
              ],
            ),
          ],
          // Allow cancelling future replacement classes
          if (!isPast && status == 'approved') ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancelReplacementClass(docId, data),
                icon: const Icon(Icons.cancel_outlined,
                    size: 18, color: Colors.red),
                label: const Text('Cancel',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancelReplacementClass(
      String docId, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Replacement Class'),
        content: const Text(
            'Are you sure you want to cancel this replacement class? The time slot will be unlocked.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Keep It'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Update status to cancelled
      await FirebaseFirestore.instance
          .collection('replacement_classes')
          .doc(docId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      // Unlock the time slot
      final dateStr = data['replacementDateStr'] as String?;
      final startTime = data['startTime'] as String?;
      final endTime = data['endTime'] as String?;
      final classId = data['classId'] as String?;

      if (dateStr != null && startTime != null && endTime != null) {
        final timeSlotStr = '$startTime-$endTime';
        final lockDocRef = FirebaseFirestore.instance
            .collection('timeLocks')
            .doc('$dateStr-$timeSlotStr');

        final lockDoc = await lockDocRef.get();
        if (lockDoc.exists) {
          final currentLocks =
              lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
          final updatedLocks = currentLocks.where((lock) {
            final lockMap = lock as Map<String, dynamic>;
            return lockMap['classId'] != classId ||
                lockMap['isReplacement'] != true;
          }).toList();

          if (updatedLocks.isEmpty) {
            await lockDocRef.delete();
          } else {
            await lockDocRef.update({'lockedBy': updatedLocks});
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Replacement class cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error cancelling: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
