import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherTimetablePage extends StatefulWidget {
  const TeacherTimetablePage({super.key});

  @override
  State<TeacherTimetablePage> createState() => _TeacherTimetablePageState();
}

class _TeacherTimetablePageState extends State<TeacherTimetablePage> {
  String? _selectedClassId;
  List<Map<String, dynamic>> _teacherClasses = [];
  bool _isLoading = false;
  
  // Week view data
  final List<String> _daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _timeSlots = [
    '9:00-11:00',
    '11:00-13:00',
    '13:00-15:00',
    '15:00-17:00',
    '17:00-19:00',
  ];
  
  // Selected schedule
  int? _selectedDayOfWeek;
  String? _selectedTimeSlot;
  
  // Locked times (from global lock collection)
  Map<String, List<Map<String, dynamic>>> _lockedTimes = {};

  @override
  void initState() {
    super.initState();
    _loadTeacherClasses();
    _loadLockedTimes();
  }

  Future<void> _loadTeacherClasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'classId': doc.id,
          'className': data['className'] ?? 'Unknown',
          'subject': data['subject'] ?? '',
        };
      }).toList();

      setState(() {
        _teacherClasses = classes;
        if (classes.isNotEmpty && _selectedClassId == null) {
          _selectedClassId = classes[0]['classId'];
        }
        _isLoading = false;
      });

      // Load existing timetable for selected class
      if (_selectedClassId != null) {
        _loadExistingTimetable(_selectedClassId!);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading classes: $e')),
        );
      }
    }
  }

  Future<void> _loadLockedTimes() async {
    try {
      // Get current month dates
      final now = DateTime.now();
      final firstDay = DateTime(now.year, now.month, 1);
      final lastDay = DateTime(now.year, now.month + 1, 0);
      
      // Load locked times for current month
      final lockedSnapshot = await FirebaseFirestore.instance
          .collection('timeLocks')
          .where('date', isGreaterThanOrEqualTo: DateFormat('yyyy-MM-dd').format(firstDay))
          .where('date', isLessThanOrEqualTo: DateFormat('yyyy-MM-dd').format(lastDay))
          .get();

      final lockedMap = <String, List<Map<String, dynamic>>>{};
      
      for (var doc in lockedSnapshot.docs) {
        final data = doc.data();
        final date = data['date'] as String;
        final timeSlot = data['timeSlot'] as String;
        final key = '$date-$timeSlot';
        
        if (!lockedMap.containsKey(key)) {
          lockedMap[key] = [];
        }
        
        final lockedBy = data['lockedBy'] as List<dynamic>? ?? [];
        lockedMap[key] = lockedBy.map((e) => e as Map<String, dynamic>).toList();
      }

      setState(() {
        _lockedTimes = lockedMap;
      });
    } catch (e) {
      print('Error loading locked times: $e');
    }
  }

  Future<void> _loadExistingTimetable(String classId) async {
    try {
      final timetableSnapshot = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', isEqualTo: classId)
          .limit(1)
          .get();

      if (timetableSnapshot.docs.isNotEmpty) {
        final timetable = timetableSnapshot.docs.first.data();
        final status = timetable['status'] as String? ?? 'pending_approval';
        
        // If status is pending, show pending changes, otherwise show base schedule
        Map<String, dynamic>? scheduleToShow;
        if (status == 'pending_approval' && timetable['pendingChanges'] != null) {
          scheduleToShow = timetable['pendingChanges'] as Map<String, dynamic>?;
        } else {
          scheduleToShow = timetable['baseSchedule'] as Map<String, dynamic>?;
        }
        
        if (scheduleToShow != null) {
          setState(() {
            _selectedDayOfWeek = scheduleToShow?['dayOfWeek'] as int?;
            final startTime = scheduleToShow?['startTime'] as String? ?? '';
            final endTime = scheduleToShow?['endTime'] as String? ?? '';
            _selectedTimeSlot = '$startTime-$endTime';
          });
        }
      }
    } catch (e) {
      print('Error loading timetable: $e');
    }
  }

  bool _isTimeLocked(int dayOfWeek, String timeSlot) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;
    
    // Check all dates in current month for this day of week
    for (int day = 1; day <= 31; day++) {
      try {
        final date = DateTime(currentYear, currentMonth, day);
        if (date.month != currentMonth) break; // Out of month
        
        // Check if this date matches the day of week
        if (date.weekday == (dayOfWeek == 0 ? 7 : dayOfWeek)) {
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final key = '$dateStr-$timeSlot';
          
          if (_lockedTimes.containsKey(key)) {
            final locks = _lockedTimes[key]!;
            // Check if locked by different class
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              for (var lock in locks) {
                if (lock['teacherId'] == user.uid && 
                    lock['classId'] != _selectedClassId) {
                  return true; // Locked by teacher's other class
                }
              }
            }
          }
        }
      } catch (e) {
        // Invalid date, skip
        continue;
      }
    }
    
    return false;
  }

  Future<void> _submitTimetable() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject')),
      );
      return;
    }

    if (_selectedDayOfWeek == null || _selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a day and time')),
      );
      return;
    }

    // Check if time is locked
    if (_isTimeLocked(_selectedDayOfWeek!, _selectedTimeSlot!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This time slot is already occupied by another class'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final classData = _teacherClasses.firstWhere(
        (c) => c['classId'] == _selectedClassId,
      );

      final startTime = _selectedTimeSlot!.split('-')[0];
      final endTime = _selectedTimeSlot!.split('-')[1];

      // Check if timetable already exists
      final existingTimetable = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', isEqualTo: _selectedClassId)
          .limit(1)
          .get();

      final now = DateTime.now();
      final currentMonth = now.month;
      final currentYear = now.year;

      if (existingTimetable.docs.isNotEmpty) {
        // Update existing timetable - only update pendingChanges, keep baseSchedule unchanged
        final timetableId = existingTimetable.docs.first.id;
        final timetableRef = FirebaseFirestore.instance
            .collection('timetables')
            .doc(timetableId);

        final existingData = existingTimetable.docs.first.data() as Map<String, dynamic>;
        final currentStatus = existingData['status'] as String? ?? 'pending_approval';

        // Only allow editing if not pending approval (unless it's for a different subject)
        if (currentStatus == 'pending_approval') {
          // Check if this is for the same class
          final existingClassId = existingData['classId'] as String?;
          if (existingClassId == _selectedClassId) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You already have a pending approval request for this subject. Please wait for admin approval.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return;
          }
        }

        // Store pending changes (don't update baseSchedule until approved)
        await timetableRef.update({
          'status': 'pending_approval',
          'lastModified': FieldValue.serverTimestamp(),
          'pendingChanges': {
            'dayOfWeek': _selectedDayOfWeek,
            'startTime': startTime,
            'endTime': endTime,
            'requestedAt': FieldValue.serverTimestamp(),
          },
        });
      } else {
        // Create new timetable
        await FirebaseFirestore.instance.collection('timetables').add({
          'classId': _selectedClassId,
          'subjectName': classData['className'],
          'teacherId': user.uid,
          'baseSchedule': {
            'dayOfWeek': _selectedDayOfWeek,
            'startTime': startTime,
            'endTime': endTime,
          },
          'status': 'pending_approval',
          'cancelledDates': [],
          'additionalSessions': [],
          'createdAt': FieldValue.serverTimestamp(),
          'lastModified': FieldValue.serverTimestamp(),
        });
      }

      // Lock all dates in current month for this time slot
      await _lockTimeSlots(_selectedDayOfWeek!, _selectedTimeSlot!, currentYear, currentMonth);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timetable submitted. Waiting for admin approval.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _lockTimeSlots(int dayOfWeek, String timeSlot, int year, int month) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final classData = _teacherClasses.firstWhere(
      (c) => c['classId'] == _selectedClassId,
    );

    // Lock all dates in the month that match the day of week
    for (int day = 1; day <= 31; day++) {
      try {
        final date = DateTime(year, month, day);
        if (date.month != month) break;

        // Check if this date matches the day of week
        if (date.weekday == (dayOfWeek == 0 ? 7 : dayOfWeek)) {
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final lockDocRef = FirebaseFirestore.instance
              .collection('timeLocks')
              .doc('$dateStr-$timeSlot');

          final lockDoc = await lockDocRef.get();
          
          if (lockDoc.exists) {
            // Update existing lock
            final currentLocks = lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
            final newLock = {
              'classId': _selectedClassId,
              'teacherId': user.uid,
              'subjectName': classData['className'],
              'timetableId': '', // Will be updated after approval
            };
            
            // Check if already locked by this class
            final exists = currentLocks.any(
              (lock) => lock['classId'] == _selectedClassId,
            );
            
            if (!exists) {
              currentLocks.add(newLock);
              await lockDocRef.update({
                'lockedBy': currentLocks,
              });
            }
          } else {
            // Create new lock
            await lockDocRef.set({
              'date': dateStr,
              'timeSlot': timeSlot,
              'lockedBy': [
                {
                  'classId': _selectedClassId,
                  'teacherId': user.uid,
                  'subjectName': classData['className'],
                  'timetableId': '',
                }
              ],
            });
          }
        }
      } catch (e) {
        continue;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Management'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading && _teacherClasses.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Subject Selection
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey.shade50,
                  child: DropdownButtonFormField<String>(
                    value: _selectedClassId,
                    decoration: const InputDecoration(
                      labelText: 'Select Subject',
                      border: OutlineInputBorder(),
                    ),
                    items: _teacherClasses.map((classData) {
                      return DropdownMenuItem<String>(
                        value: classData['classId'],
                        child: Text(classData['className'] ?? 'Unknown'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value;
                        _selectedDayOfWeek = null;
                        _selectedTimeSlot = null;
                      });
                      if (value != null) {
                        _loadExistingTimetable(value);
                      }
                    },
                  ),
                ),

                // Week View
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Day and Time',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        
                        // Days of Week
                        const Text('Day of Week:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (index) {
                            final isSelected = _selectedDayOfWeek == index;
                            final isLocked = _selectedTimeSlot != null && 
                                _isTimeLocked(index, _selectedTimeSlot!);
                            
                            return GestureDetector(
                              onTap: isLocked ? null : () {
                                setState(() {
                                  _selectedDayOfWeek = index;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isLocked
                                      ? Colors.grey.shade300
                                      : isSelected
                                          ? Colors.blue
                                          : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _daysOfWeek[index],
                                  style: TextStyle(
                                    color: isLocked
                                        ? Colors.grey.shade600
                                        : isSelected
                                            ? Colors.white
                                            : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 24),
                        
                        // Time Slots
                        const Text('Time Slot:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _timeSlots.map((slot) {
                            final isSelected = _selectedTimeSlot == slot;
                            final isLocked = _selectedDayOfWeek != null && 
                                _isTimeLocked(_selectedDayOfWeek!, slot);
                            
                            return GestureDetector(
                              onTap: isLocked ? null : () {
                                setState(() {
                                  _selectedTimeSlot = slot;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isLocked
                                      ? Colors.grey.shade300
                                      : isSelected
                                          ? Colors.blue
                                          : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  slot,
                                  style: TextStyle(
                                    color: isLocked
                                        ? Colors.grey.shade600
                                        : isSelected
                                            ? Colors.white
                                            : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        // Status Info
                        if (_selectedClassId != null)
                          FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('timetables')
                                .where('classId', isEqualTo: _selectedClassId)
                                .limit(1)
                                .get(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                final timetable = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                                final status = timetable['status'] as String? ?? 'pending_approval';
                                
                                Color statusColor;
                                String statusText;
                                switch (status) {
                                  case 'approved':
                                    statusColor = Colors.green;
                                    statusText = 'Approved';
                                    break;
                                  case 'rejected':
                                    statusColor = Colors.red;
                                    statusText = 'Rejected';
                                    break;
                                  default:
                                    statusColor = Colors.orange;
                                    statusText = 'Pending Approval';
                                }

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: statusColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Status: $statusText',
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                      ],
                    ),
                  ),
                ),

                // Submit Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitTimetable,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit for Approval',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
