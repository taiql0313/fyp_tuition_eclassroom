import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentTimetablePage extends StatefulWidget {
  const StudentTimetablePage({super.key});

  @override
  State<StudentTimetablePage> createState() => _StudentTimetablePageState();
}

class _StudentTimetablePageState extends State<StudentTimetablePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _enrolledClasses = [];
  Map<String, Map<String, dynamic>> _timetables = {};
  Map<String, String> _teacherNames = {};
  Map<String, List<Map<String, dynamic>>> _replacementClasses = {};
  bool _isLoading = true;

  final List<String> _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    // Set initial tab to current day (Monday = 0, Sunday = 6)
    final today = DateTime.now().weekday - 1; // weekday: 1=Mon, 7=Sun -> 0-6
    _tabController.index = today;
    _tabController.addListener(_onTabChanged);
    _loadEnrolledClasses();
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
    final currentWeekday = now.weekday; // 1=Mon, 7=Sun
    final targetWeekday = dayIndex + 1; // Convert 0-6 to 1-7
    final diff = targetWeekday - currentWeekday;
    return DateTime(now.year, now.month, now.day + diff);
  }

  Future<void> _loadEnrolledClasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data();
      final classIds = List<String>.from(userData?['classIds'] ?? []);

      if (classIds.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where(FieldPath.documentId, whereIn: classIds)
          .get();

      _enrolledClasses = [];
      final teacherIds = <String>{};

      for (var doc in classesSnapshot.docs) {
        final data = doc.data();
        final teacherId = data['teacherId'] as String?;
        if (teacherId != null) teacherIds.add(teacherId);

        _enrolledClasses.add({
          'classId': doc.id,
          'className': data['className'] ?? 'Unknown',
          'subject': data['subject'] ?? '',
          'teacherId': teacherId ?? '',
        });
      }

      // Fetch teacher names
      await _loadTeacherNames(teacherIds.toList());

      // Load timetables and approved replacement classes
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

  Future<void> _loadTeacherNames(List<String> teacherIds) async {
    if (teacherIds.isEmpty) return;

    try {
      // Firestore whereIn limit is 10, so batch if needed
      for (var i = 0; i < teacherIds.length; i += 10) {
        final batch = teacherIds.skip(i).take(10).toList();
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          _teacherNames[doc.id] = data['displayName'] ?? 'Unknown Teacher';
        }
      }
    } catch (e) {
      print('Error loading teacher names: $e');
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

  Future<void> _loadReplacementClasses(List<String> classIds) async {
    _replacementClasses = {};
    try {
      if (classIds.isEmpty) return;

      // Firestore whereIn limit is 10
      for (var i = 0; i < classIds.length; i += 10) {
        final batch = classIds.skip(i).take(10).toList();

        final snapshot = await FirebaseFirestore.instance
            .collection('replacement_classes')
            .where('classId', whereIn: batch)
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          // Only show approved replacement classes
          if (data['status'] != 'approved') continue;

          final classId = data['classId'] as String? ?? '';
          if (classId.isEmpty) continue;

          final list = _replacementClasses.putIfAbsent(classId, () => []);
          list.add({
            'originalDateStr': data['originalDateStr'] as String?,
            'replacementDateStr': data['replacementDateStr'] as String?,
            'startTime': data['startTime'] as String? ?? '',
            'endTime': data['endTime'] as String? ?? '',
          });
        }
      }
    } catch (e) {
      print('Error loading replacement classes: $e');
    }
  }

  List<Map<String, dynamic>> _getClassesForDay(int dayIndex) {
    // dayIndex: 0=Mon, 1=Tue, ..., 6=Sun
    // Convert to stored format: 1=Mon, 2=Tue, ..., 7=Sun (or 0=Sun depending on your data)
    final targetDayOfWeek = dayIndex + 1; // 1-7 (Mon-Sun)
    final classesForDay = <Map<String, dynamic>>[];
    final dateForDay = _getDateForDayIndex(dayIndex);
    final dateStr = DateFormat('yyyy-MM-dd').format(dateForDay);

    for (var classData in _enrolledClasses) {
      final classId = classData['classId'] as String;
      final timetable = _timetables[classId];
      final replacements = _replacementClasses[classId] ?? [];

      // If there is an approved replacement whose originalDate is this date,
      // we treat the original weekly session as cancelled for this date.
      final isOriginalCancelledHere = replacements.any(
        (r) => r['originalDateStr'] == dateStr,
      );

      // If there is an approved replacement whose replacementDate is this date,
      // we show the replacement session on this date (even if on a different weekday).
      final replacementForThisDate = replacements.firstWhere(
        (r) => r['replacementDateStr'] == dateStr,
        orElse: () => {},
      );

      if (replacementForThisDate.isNotEmpty) {
        final teacherId = classData['teacherId'] as String;
        final teacherName = _teacherNames[teacherId] ?? 'Unknown Teacher';

        classesForDay.add({
          'classId': classId,
          'className': classData['className'],
          'subject': classData['subject'],
          'teacherName': teacherName,
          'startTime': replacementForThisDate['startTime'] ?? '',
          'endTime': replacementForThisDate['endTime'] ?? '',
          'isReplacement': true,
        });
        // Continue to next class; do not also add base schedule for this date
        continue;
      }

      if (timetable != null) {
        final baseSchedule = timetable['baseSchedule'] as Map<String, dynamic>?;
        if (baseSchedule != null) {
          int? scheduleDayOfWeek = baseSchedule['dayOfWeek'] as int?;
          
          // Handle different day formats (0=Sun vs 1=Mon)
          // If stored as 0=Sun, 1=Mon, ..., 6=Sat, convert
          if (scheduleDayOfWeek != null) {
            // Assuming stored as 0=Sun, 1=Mon, ..., 6=Sat
            // Convert to 1=Mon, ..., 7=Sun
            int convertedDay;
            if (scheduleDayOfWeek == 0) {
              convertedDay = 7; // Sunday
            } else {
              convertedDay = scheduleDayOfWeek; // Mon=1, Tue=2, etc.
            }

            if (convertedDay == targetDayOfWeek && !isOriginalCancelledHere) {
              final teacherId = classData['teacherId'] as String;
              final teacherName = _teacherNames[teacherId] ?? 'Unknown Teacher';

              classesForDay.add({
                'classId': classId,
                'className': classData['className'],
                'subject': classData['subject'],
                'teacherName': teacherName,
                'startTime': baseSchedule['startTime'] ?? '',
                'endTime': baseSchedule['endTime'] ?? '',
                'isReplacement': false,
              });
            }
          }
        }
      }
    }

    // Sort by start time
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
        appBar: AppBar(title: const Text('Class Timetable')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Timetable'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: theme.appBarTheme.backgroundColor ?? primaryColor,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: theme.appBarTheme.foregroundColor ?? Colors.white,
              unselectedLabelColor: (theme.appBarTheme.foregroundColor ?? Colors.white).withOpacity(0.6),
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
          // Date header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEEE').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yyyy').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Tab content
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

  Widget _buildDaySchedule(int dayIndex) {
    final classes = _getClassesForDay(dayIndex);
    final theme = Theme.of(context);

    if (classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No classes scheduled',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final classData = classes[index];
        return _buildClassCard(classData, index);
      },
    );
  }

  Widget _buildClassCard(Map<String, dynamic> classData, int index) {
    final theme = Theme.of(context);
    final startTime = _formatTime(classData['startTime'] as String);
    final endTime = _formatTime(classData['endTime'] as String);
    final className = classData['className'] as String;
    final teacherName = classData['teacherName'] as String;
    final isReplacement = (classData['isReplacement'] as bool?) ?? false;

    // Alternate colors for visual distinction
    final colors = [
      const Color(0xFF5C6BC0), // Indigo
      const Color(0xFF8D6E63), // Brown
      const Color(0xFF26A69A), // Teal
      const Color(0xFFEC407A), // Pink
      const Color(0xFF7E57C2), // Deep Purple
      const Color(0xFF42A5F5), // Blue
    ];
    final cardColor = colors[index % colors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  startTime,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  endTime,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // Class card
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
                  // Teacher name
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          teacherName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
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
