import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherTimetableViewPage extends StatefulWidget {
  const TeacherTimetableViewPage({super.key});

  @override
  State<TeacherTimetableViewPage> createState() => _TeacherTimetableViewPageState();
}

class _TeacherTimetableViewPageState extends State<TeacherTimetableViewPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _weekOffset = 0;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _teacherClasses = [];
  Map<String, Map<String, dynamic>> _timetables = {};
  Map<String, int> _studentCounts = {};
  Map<String, List<Map<String, dynamic>>> _replacementClasses = {};
  Map<String, List<String>> _cancelledDates = {};
  bool _isLoading = true;

  final List<String> _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    final today = DateTime.now().weekday - 1;
    _tabController.index = today;
    _tabController.addListener(_onTabChanged);
    _loadTeacherClasses();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _selectedDate = _getDateForDayIndex(_tabController.index);
      });
    }
  }

  DateTime _getDateForDayIndex(int dayIndex) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    final targetWeekday = dayIndex + 1;
    final diff = targetWeekday - currentWeekday + (_weekOffset * 7);
    return DateTime(now.year, now.month, now.day + diff);
  }

  void _changeWeek(int delta) {
    final newOffset = _weekOffset + delta;
    if (newOffset < 0 || newOffset > 1) return;
    setState(() {
      _weekOffset = newOffset;
      _selectedDate = _getDateForDayIndex(_tabController.index);
    });
  }

  Future<void> _loadTeacherClasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      _teacherClasses = [];
      final classIds = <String>[];

      for (var doc in classesSnapshot.docs) {
        final data = doc.data();
        if (data['isArchived'] == true) continue;

        classIds.add(doc.id);
        _teacherClasses.add({
          'classId': doc.id,
          'className': data['className'] ?? 'Unknown',
          'subject': data['subject'] ?? '',
        });
      }

      await _loadStudentCounts(classIds);
      await _loadTimetables(classIds);
      await _loadReplacementClasses(classIds);

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

  Future<void> _loadStudentCounts(List<String> classIds) async {
    for (var classId in classIds) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('classIds', arrayContains: classId)
            .where('role', isEqualTo: 'student')
            .get();
        _studentCounts[classId] = snapshot.docs.length;
      } catch (_) {
        _studentCounts[classId] = 0;
      }
    }
  }

  Future<void> _loadTimetables(List<String> classIds) async {
    if (classIds.isEmpty) return;
    try {
      for (var i = 0; i < classIds.length; i += 10) {
        final batch = classIds.skip(i).take(10).toList();
        final snapshot = await FirebaseFirestore.instance
            .collection('timetables')
            .where('classId', whereIn: batch)
            .where('status', isEqualTo: 'approved')
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final classId = data['classId'] as String;
          _timetables[classId] = data;

          final cancelled = data['cancelledDates'] as List<dynamic>? ?? [];
          _cancelledDates[classId] = cancelled.map((c) {
            if (c is Map) return c['date'] as String? ?? '';
            return c.toString();
          }).where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (e) {
      print('Error loading timetables: $e');
    }
  }

  Future<void> _loadReplacementClasses(List<String> classIds) async {
    _replacementClasses = {};
    if (classIds.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Query by teacherId to satisfy Firestore security rules
      // (rules require resource.data.teacherId == request.auth.uid for teachers)
      final snapshot = await FirebaseFirestore.instance
          .collection('replacement_classes')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      final classIdSet = classIds.toSet();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] != 'approved') continue;
        final classId = data['classId'] as String? ?? '';
        if (classId.isEmpty || !classIdSet.contains(classId)) continue;

        _replacementClasses.putIfAbsent(classId, () => []).add({
          'originalDateStr': data['originalDateStr'] as String?,
          'replacementDateStr': data['replacementDateStr'] as String?,
          'startTime': data['startTime'] as String? ?? '',
          'endTime': data['endTime'] as String? ?? '',
        });
      }
    } catch (e) {
      print('Error loading replacement classes: $e');
    }
  }

  List<Map<String, dynamic>> _getClassesForDay(int dayIndex) {
    final targetDayOfWeek = dayIndex + 1;
    final classesForDay = <Map<String, dynamic>>[];
    final dateForDay = _getDateForDayIndex(dayIndex);
    final dateStr = DateFormat('yyyy-MM-dd').format(dateForDay);

    for (var classData in _teacherClasses) {
      final classId = classData['classId'] as String;
      final timetable = _timetables[classId];
      final replacements = _replacementClasses[classId] ?? [];
      final cancelled = _cancelledDates[classId] ?? [];

      final isOriginalCancelledHere = replacements.any(
        (r) => r['originalDateStr'] == dateStr,
      );

      final isCancelledHere = cancelled.contains(dateStr);

      final replacementForThisDate = replacements.firstWhere(
        (r) => r['replacementDateStr'] == dateStr,
        orElse: () => {},
      );

      if (replacementForThisDate.isNotEmpty) {
        classesForDay.add({
          'classId': classId,
          'className': classData['className'],
          'subject': classData['subject'],
          'studentCount': _studentCounts[classId] ?? 0,
          'startTime': replacementForThisDate['startTime'] ?? '',
          'endTime': replacementForThisDate['endTime'] ?? '',
          'isReplacement': true,
        });
        continue;
      }

      if (timetable != null) {
        final baseSchedule = timetable['baseSchedule'] as Map<String, dynamic>?;
        if (baseSchedule != null) {
          int? scheduleDayOfWeek = baseSchedule['dayOfWeek'] as int?;
          if (scheduleDayOfWeek != null) {
            int convertedDay;
            if (scheduleDayOfWeek == 0) {
              convertedDay = 7;
            } else {
              convertedDay = scheduleDayOfWeek;
            }

            if (convertedDay == targetDayOfWeek &&
                !isOriginalCancelledHere &&
                !isCancelledHere) {
              classesForDay.add({
                'classId': classId,
                'className': classData['className'],
                'subject': classData['subject'],
                'studentCount': _studentCounts[classId] ?? 0,
                'startTime': baseSchedule['startTime'] ?? '',
                'endTime': baseSchedule['endTime'] ?? '',
                'isReplacement': false,
              });
            }
          }
        }
      }
    }

    classesForDay.sort((a, b) {
      final aTime = a['startTime'] as String;
      final bTime = b['startTime'] as String;
      return aTime.compareTo(bTime);
    });

    return classesForDay;
  }

  String _formatTime(String time24) {
    if (time24.isEmpty) return '';
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? parts[1] : '00';
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour12:$minute $period';
    } catch (e) {
      return time24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Timetable')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Timetable'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: theme.appBarTheme.backgroundColor ?? primaryColor,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: theme.appBarTheme.foregroundColor ?? Colors.white,
              unselectedLabelColor:
                  (theme.appBarTheme.foregroundColor ?? Colors.white).withOpacity(0.6),
              indicatorColor: theme.appBarTheme.foregroundColor ?? Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
              tabs: _dayNames.map((day) => Tab(text: day)).toList(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildWeekHeader(theme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(7, (index) => _buildDaySchedule(index)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1458A3)),
            onPressed: _weekOffset > 0 ? () => _changeWeek(-1) : null,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _weekOffset == 0 ? 'This Week' : 'Next Week',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1458A3),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('EEEE').format(_selectedDate)}  •  ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF1458A3)),
            onPressed: _weekOffset < 1 ? () => _changeWeek(1) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule(int dayIndex) {
    final classes = _getClassesForDay(dayIndex);

    if (classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No classes scheduled',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: classes.length,
      itemBuilder: (context, index) => _buildClassCard(classes[index], index),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> classData, int index) {
    final theme = Theme.of(context);
    final startTime = _formatTime(classData['startTime'] as String);
    final endTime = _formatTime(classData['endTime'] as String);
    final className = classData['className'] as String;
    final studentCount = classData['studentCount'] as int;
    final isReplacement = (classData['isReplacement'] as bool?) ?? false;

    final colors = [
      const Color(0xFF1458A3),
      const Color(0xFF1976D2),
      const Color(0xFF1565C0),
      const Color(0xFF0D47A1),
      const Color(0xFF1E88E5),
      const Color(0xFF1A5FA3),
    ];
    final cardColor = colors[index % colors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  startTime,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1458A3),
                  ),
                ),
                Text(
                  endTime,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1458A3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: cardColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          className.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isReplacement)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Replacement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.people, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        '$studentCount student${studentCount != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
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
