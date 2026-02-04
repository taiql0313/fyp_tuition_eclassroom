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
  bool _isLoadingLocks = true; // Track if locks are still loading
  
  // Week view data
  final List<String> _daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final List<String> _timeSlots = [
    '09:00-11:00',
    '11:00-13:00',
    '13:00-15:00',
    '15:00-17:00',
    '17:00-19:00',
    '16:00-18:00', // Added to match existing classroom times
  ];
  
  // Selected schedule
  int? _selectedDayOfWeek;
  String? _selectedTimeSlot;
  
  // Locked times (from global lock collection)
  Map<String, List<Map<String, dynamic>>> _lockedTimes = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }
  
  Future<void> _initializeData() async {
    await _loadLockedTimes(); // Load locks first
    await _loadTeacherClasses(); // Then load classes
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
    setState(() => _isLoadingLocks = true);
    
    try {
      // Load ALL classrooms to check for time conflicts
      // Your teammate stores time in classrooms collection directly
      final classroomsSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .get();

      print('DEBUG: Found ${classroomsSnapshot.docs.length} classroom documents');

      final lockedMap = <String, List<Map<String, dynamic>>>{};
      
      for (var doc in classroomsSnapshot.docs) {
        final data = doc.data();
        final day = data['day'] as String?; // e.g., "Friday"
        final timeStart = data['timeStart'] as String?; // e.g., "16:00"
        final timeEnd = data['timeEnd'] as String?; // e.g., "18:00"
        final classId = doc.id;
        final className = data['className'] as String? ?? 'Unknown';
        
        print('DEBUG: Classroom ${doc.id} - day: $day, timeStart: $timeStart, timeEnd: $timeEnd');
        
        if (day == null || timeStart == null || timeEnd == null) continue;
        
        // Convert day name to index (0=Sun, 1=Mon, etc.)
        final dayIndex = _getDayIndex(day);
        if (dayIndex == -1) continue;
        
        // Create time slot string
        final timeSlot = '$timeStart-$timeEnd';
        final key = '$dayIndex-$timeSlot';
        
        if (!lockedMap.containsKey(key)) {
          lockedMap[key] = [];
        }
        
        lockedMap[key]!.add({
          'classId': classId,
          'className': className,
          'day': day,
          'timeStart': timeStart,
          'timeEnd': timeEnd,
        });
        
        print('DEBUG: Added lock - key: $key, classId: $classId, className: $className');
      }

      print('DEBUG: Total locked time slots: ${lockedMap.length}');
      print('DEBUG: All keys: ${lockedMap.keys.toList()}');
      
      setState(() {
        _lockedTimes = lockedMap;
        _isLoadingLocks = false;
      });
    } catch (e) {
      print('Error loading locked times: $e');
      setState(() => _isLoadingLocks = false);
    }
  }
  
  // Convert day name to index
  int _getDayIndex(String dayName) {
    switch (dayName.toLowerCase()) {
      case 'sunday': return 0;
      case 'monday': return 1;
      case 'tuesday': return 2;
      case 'wednesday': return 3;
      case 'thursday': return 4;
      case 'friday': return 5;
      case 'saturday': return 6;
      default: return -1;
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

  // Real-time conflict check against Firestore (not local cache)
  Future<bool> _checkRealTimeConflict(int dayOfWeek, String timeSlot) async {
    try {
      // Convert day index to day name
      final dayName = _daysOfWeek[dayOfWeek]; // e.g., "Fri"
      final fullDayName = _getFullDayName(dayOfWeek); // e.g., "Friday"
      
      final parts = timeSlot.split('-');
      if (parts.length != 2) return false;
      
      final timeStart = parts[0]; // e.g., "16:00"
      final timeEnd = parts[1];   // e.g., "18:00"
      
      print('DEBUG _checkRealTimeConflict: Checking day=$fullDayName, timeStart=$timeStart, timeEnd=$timeEnd');
      print('DEBUG _checkRealTimeConflict: selectedClassId=$_selectedClassId');
      
      // Query ALL classrooms and filter manually (avoid compound index requirement)
      final snapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .get();
      
      print('DEBUG _checkRealTimeConflict: Found ${snapshot.docs.length} total classrooms');
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final docDay = data['day'] as String?;
        final docTimeStart = data['timeStart'] as String?;
        final docTimeEnd = data['timeEnd'] as String?;
        
        print('DEBUG _checkRealTimeConflict: Checking classroom ${doc.id} - day=$docDay, timeStart=$docTimeStart, timeEnd=$docTimeEnd');
        
        // Check if this classroom matches the selected time slot
        if (docDay == fullDayName && 
            docTimeStart == timeStart && 
            docTimeEnd == timeEnd &&
            doc.id != _selectedClassId) {
          print('DEBUG _checkRealTimeConflict: CONFLICT FOUND with classroom ${doc.id}');
          return true; // Conflict found
        }
      }
      
      return false;
    } catch (e) {
      print('Error in real-time conflict check: $e');
      return false;
    }
  }
  
  // Get full day name from index
  String _getFullDayName(int dayIndex) {
    switch (dayIndex) {
      case 0: return 'Sunday';
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      default: return '';
    }
  }
  
  // Format time for display (e.g., "16:00-18:00" -> "4:00 PM - 6:00 PM")
  String _formatTimeDisplay(String startTime, String endTime) {
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      
      int startHour = int.parse(startParts[0]);
      int endHour = int.parse(endParts[0]);
      String startMin = startParts[1];
      String endMin = endParts[1];
      
      String startPeriod = startHour >= 12 ? 'PM' : 'AM';
      String endPeriod = endHour >= 12 ? 'PM' : 'AM';
      
      if (startHour > 12) startHour -= 12;
      if (startHour == 0) startHour = 12;
      if (endHour > 12) endHour -= 12;
      if (endHour == 0) endHour = 12;
      
      return '$startHour:$startMin $startPeriod - $endHour:$endMin $endPeriod';
    } catch (e) {
      return '$startTime - $endTime';
    }
  }

  bool _isTimeLocked(int dayOfWeek, String timeSlot) {
    // New approach: Check against classrooms collection
    // Key format: dayIndex-timeSlot (e.g., "5-16:00-18:00")
    final key = '$dayOfWeek-$timeSlot';
    
    print('DEBUG _isTimeLocked: key=$key, selectedClassId=$_selectedClassId');
    print('DEBUG _isTimeLocked: available keys=${_lockedTimes.keys.toList()}');
    
    if (_lockedTimes.containsKey(key)) {
      final locks = _lockedTimes[key]!;
      print('DEBUG _isTimeLocked: Found ${locks.length} locks for key: $key');
      
      // Check if ANY class has locked this slot (except current class)
      for (var lock in locks) {
        final lockClassId = lock['classId'];
        print('DEBUG _isTimeLocked: Comparing lockClassId=$lockClassId with selectedClassId=$_selectedClassId');
        
        // If locked by ANY different class, it's unavailable
        if (lockClassId != null && lockClassId != _selectedClassId) {
          print('DEBUG _isTimeLocked: LOCKED! classId: $lockClassId (${lock['className']})');
          return true; // Locked by another class
        } else {
          print('DEBUG _isTimeLocked: Same class, not locked');
        }
      }
    } else {
      print('DEBUG _isTimeLocked: Key not found in locked times');
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

    print('DEBUG _submitTimetable: Starting submit - day=$_selectedDayOfWeek, time=$_selectedTimeSlot, classId=$_selectedClassId');
    
    // Check if time is locked (local cache)
    final isLocked = _isTimeLocked(_selectedDayOfWeek!, _selectedTimeSlot!);
    print('DEBUG _submitTimetable: Local lock check result = $isLocked');
    
    if (isLocked) {
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
    
    // Real-time conflict check against Firestore
    final hasConflict = await _checkRealTimeConflict(_selectedDayOfWeek!, _selectedTimeSlot!);
    print('DEBUG _submitTimetable: Real-time conflict check result = $hasConflict');
    
    if (hasConflict) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This time slot was just taken by another class. Please select a different time.'),
            backgroundColor: Colors.red,
          ),
        );
        // Refresh locked times
        await _loadLockedTimes();
      }
      return;
    }

    try {
      final startTime = _selectedTimeSlot!.split('-')[0];
      final endTime = _selectedTimeSlot!.split('-')[1];
      final dayName = _getFullDayName(_selectedDayOfWeek!);
      
      // Format classTime for display (e.g., "4:00 PM - 6:00 PM")
      final classTimeDisplay = _formatTimeDisplay(startTime, endTime);

      // Update the classroom document directly with the schedule
      await FirebaseFirestore.instance
          .collection('classrooms')
          .doc(_selectedClassId)
          .update({
        'day': dayName,
        'timeStart': startTime,
        'timeEnd': endTime,
        'classTime': classTimeDisplay,
      });
      
      print('DEBUG: Updated classroom $_selectedClassId with day: $dayName, time: $startTime-$endTime');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timetable saved successfully!'),
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
                    onChanged: (value) async {
                      setState(() {
                        _selectedClassId = value;
                        _selectedDayOfWeek = null;
                        _selectedTimeSlot = null;
                      });
                      if (value != null) {
                        // Refresh locked times when changing subject
                        await _loadLockedTimes();
                        _loadExistingTimetable(value);
                      }
                    },
                  ),
                ),

                // Week View
                Expanded(
                  child: _isLoadingLocks 
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading time slots...'),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Day and Time',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        
                        // Show locked slots count
                        Text(
                          'Locked slots: ${_lockedTimes.length}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
