import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentTimetablePage extends StatefulWidget {
  const StudentTimetablePage({super.key});

  @override
  State<StudentTimetablePage> createState() => _StudentTimetablePageState();
}

class _StudentTimetablePageState extends State<StudentTimetablePage> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _enrolledClasses = [];
  Map<String, Map<String, dynamic>> _timetables = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEnrolledClasses();
  }

  Future<void> _loadEnrolledClasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Get student's enrolled classes
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data();
      final classIds = List<String>.from(userData?['classIds'] ?? []);

      if (classIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get classroom data
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where(FieldPath.documentId, whereIn: classIds)
          .get();

      _enrolledClasses = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'classId': doc.id,
          'className': data['className'] ?? 'Unknown',
          'subject': data['subject'] ?? '',
        };
      }).toList();

      // Load timetables for all enrolled classes
      await _loadTimetables(classIds);

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading classes: $e')),
        );
      }
    }
  }

  Future<void> _loadTimetables(List<String> classIds) async {
    try {
      final timetablesSnapshot = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', whereIn: classIds)
          .where('status', isEqualTo: 'approved')
          .get();

      for (var doc in timetablesSnapshot.docs) {
        final data = doc.data();
        final classId = data['classId'] as String;
        _timetables[classId] = data;
      }
    } catch (e) {
      print('Error loading timetables: $e');
    }
  }

  List<Map<String, dynamic>> _getClassesForDate(DateTime date) {
    final dayOfWeek = date.weekday == 7 ? 0 : date.weekday; // Convert to 0-6 (Sun-Sat)
    final classesForDay = <Map<String, dynamic>>[];

    for (var classData in _enrolledClasses) {
      final classId = classData['classId'] as String;
      final timetable = _timetables[classId];

      if (timetable != null) {
        final baseSchedule = timetable['baseSchedule'] as Map<String, dynamic>?;
        if (baseSchedule != null) {
          final scheduleDayOfWeek = baseSchedule['dayOfWeek'] as int?;
          
          if (scheduleDayOfWeek == dayOfWeek) {
            // Check if this date is cancelled
            final cancelledDates = timetable['cancelledDates'] as List<dynamic>? ?? [];
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            final isCancelled = cancelledDates.any(
              (cancelled) => cancelled['date'] == dateStr,
            );

            if (!isCancelled) {
              classesForDay.add({
                'classId': classId,
                'className': classData['className'],
                'subject': classData['subject'],
                'startTime': baseSchedule['startTime'] ?? '',
                'endTime': baseSchedule['endTime'] ?? '',
              });
            }
          }
        }
      }
    }

    return classesForDay;
  }

  Future<void> _exportTimetable() async {
    try {
      // Generate iCal format
      final buffer = StringBuffer();
      buffer.writeln('BEGIN:VCALENDAR');
      buffer.writeln('VERSION:2.0');
      buffer.writeln('PRODID:-//Tuition E-Classroom//Timetable//EN');
      buffer.writeln('CALSCALE:GREGORIAN');
      buffer.writeln('METHOD:PUBLISH');

      final now = DateTime.now();
      final firstDay = DateTime(now.year, now.month, 1);
      final lastDay = DateTime(now.year, now.month + 1, 0);

      for (int day = 1; day <= lastDay.day; day++) {
        final date = DateTime(now.year, now.month, day);
        final classes = _getClassesForDate(date);

        for (var classData in classes) {
          final startTime = classData['startTime'] as String;
          final endTime = classData['endTime'] as String;
          final className = classData['className'] as String;

          // Parse time
          final startParts = startTime.split(':');
          final endParts = endTime.split(':');
          final startHour = int.parse(startParts[0]);
          final startMin = int.parse(startParts[1]);
          final endHour = int.parse(endParts[0]);
          final endMin = int.parse(endParts[1]);

          final startDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            startHour,
            startMin,
          );
          final endDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            endHour,
            endMin,
          );

          buffer.writeln('BEGIN:VEVENT');
          buffer.writeln('DTSTART:${DateFormat('yyyyMMddTHHmmss').format(startDateTime)}');
          buffer.writeln('DTEND:${DateFormat('yyyyMMddTHHmmss').format(endDateTime)}');
          buffer.writeln('SUMMARY:$className');
          buffer.writeln('DESCRIPTION:Class: $className');
          buffer.writeln('END:VEVENT');
        }
      }

      buffer.writeln('END:VCALENDAR');

      // Show share dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Timetable'),
            content: const Text('Timetable exported. You can copy the content below.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final startWeekday = firstDay.weekday == 7 ? 0 : firstDay.weekday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timetable'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportTimetable,
            tooltip: 'Export Timetable',
          ),
        ],
      ),
      body: Column(
        children: [
          // Month Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                    });
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month + 1,
                      );
                    });
                  },
                ),
              ],
            ),
          ),

          // Calendar View
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day Headers
                  Row(
                    children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                        .map((day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 8),

                  // Calendar Grid
                  ...List.generate(
                    (daysInMonth + startWeekday + 6) ~/ 7,
                    (weekIndex) {
                      return Row(
                        children: List.generate(7, (dayIndex) {
                          final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;
                          
                          if (dayNumber < 1 || dayNumber > daysInMonth) {
                            return const Expanded(child: SizedBox());
                          }

                          final date = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month,
                            dayNumber,
                          );
                          final classes = _getClassesForDate(date);
                          final isToday = date.year == DateTime.now().year &&
                              date.month == DateTime.now().month &&
                              date.day == DateTime.now().day;

                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isToday ? Colors.blue.shade50 : Colors.white,
                                border: Border.all(
                                  color: isToday ? Colors.blue : Colors.grey.shade300,
                                  width: isToday ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$dayNumber',
                                    style: TextStyle(
                                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                      color: isToday ? Colors.blue : Colors.black,
                                    ),
                                  ),
                                  if (classes.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    ...classes.take(2).map((classData) {
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 2),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${classData['startTime']} ${classData['className']}',
                                          style: const TextStyle(fontSize: 8),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }),
                                    if (classes.length > 2)
                                      Text(
                                        '+${classes.length - 2} more',
                                        style: const TextStyle(fontSize: 8, color: Colors.grey),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
