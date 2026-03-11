import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Teacher view of attendance analytics.
/// This reuses the admin attendance report design but automatically
/// filters data to only the classes taught by the logged-in teacher.
class TeacherAttendanceReportPage extends StatefulWidget {
  const TeacherAttendanceReportPage({super.key});

  @override
  State<TeacherAttendanceReportPage> createState() =>
      _TeacherAttendanceReportPageState();
}

class _TeacherAttendanceReportPageState
    extends State<TeacherAttendanceReportPage> {
  static const Color _primaryColor = Color(0xff1458a3);
  static const Color _accentColor = Color(0xff7b1fa2);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _rateFilter = 'All';
  String _sortBy = 'Rate (Low)';
  String? _selectedClassId;
  DateTimeRange? _selectedDateRange;

  bool _loading = true;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _classes = [];

  // Stats
  int _avgAttendance = 0;
  int _lowAttendanceCount = 0;
  int _totalRecords = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      // Load only the teacher's classes
      final classesSnapshot = await _db
          .collection('classrooms')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': '${data['subject'] ?? ''} - ${data['className'] ?? ''}',
        };
      }).toList();

      // Load students only from these classes
      if (classesSnapshot.docs.isEmpty) {
        setState(() {
          _classes = classes;
          _students = [];
          _avgAttendance = 0;
          _lowAttendanceCount = 0;
          _totalRecords = 0;
          _loading = false;
        });
        return;
      }

      final classIds = classesSnapshot.docs.map((c) => c.id).toList();

      // Students who are in any of the teacher's classes
      final studentsSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('classIds', arrayContainsAny: classIds)
          .get();

      List<Map<String, dynamic>> studentsWithStats = [];

      for (var studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final studentId = studentDoc.id;
        final studentClassIds = List<String>.from(studentData['classIds'] ?? []);

        // Intersect with teacher's classes
        final teacherClassIds =
            studentClassIds.where((id) => classIds.contains(id)).toList();
        if (teacherClassIds.isEmpty) continue;

        // Apply optional class filter
        if (_selectedClassId != null && !teacherClassIds.contains(_selectedClassId)) {
          continue;
        }

        // Load attendance records for this student for the teacher's classes
        QuerySnapshot<Map<String, dynamic>> recordsSnapshot;
        if (_selectedClassId != null) {
          recordsSnapshot = await _db
              .collection('attendance_records')
              .where('studentId', isEqualTo: studentId)
              .where('classId', isEqualTo: _selectedClassId)
              .get();
        } else {
          recordsSnapshot = await _db
              .collection('attendance_records')
              .where('studentId', isEqualTo: studentId)
              .where('classId', whereIn: teacherClassIds.length > 10
                  ? teacherClassIds.take(10).toList()
                  : teacherClassIds)
              .get();
        }

        int present = 0;
        int absent = 0;
        int excused = 0;

        for (var recordDoc in recordsSnapshot.docs) {
          final recordData = recordDoc.data();
          final status = recordData['status'] as String? ?? 'absent';

          // Date filter
          if (_selectedDateRange != null) {
            final timestamp =
                (recordData['timestamp'] as Timestamp?)?.toDate();
            if (timestamp != null) {
              if (timestamp.isBefore(_selectedDateRange!.start) ||
                  timestamp.isAfter(
                      _selectedDateRange!.end.add(const Duration(days: 1)))) {
                continue;
              }
            }
          }

          if (status == 'present') {
            present++;
          } else if (status == 'excused') {
            excused++;
          } else {
            absent++;
          }
        }

        final total = present + absent + excused;
        final rate =
            total > 0 ? (((present + excused) / total) * 100).round() : 0;

        // Build display class name (for filter or first matching class)
        String displayClass = 'No class';
        if (_selectedClassId != null) {
          final selectedClass = classes.firstWhere(
            (c) => c['id'] == _selectedClassId,
            orElse: () => {'name': 'Unknown'},
          );
          displayClass = selectedClass['name'] as String;
        } else {
          final firstClassId = teacherClassIds.first;
          final firstClass = classes.firstWhere(
            (c) => c['id'] == firstClassId,
            orElse: () => {'name': 'Unknown'},
          );
          displayClass = firstClass['name'] as String;
        }

        studentsWithStats.add({
          'id': studentId,
          'name': studentData['displayName'] ?? 'Unknown Student',
          'email': studentData['email'] ?? '',
          'class': displayClass,
          'classIds': teacherClassIds,
          'rate': rate,
          'present': present,
          'absent': absent,
          'excused': excused,
          'total': total,
        });
      }

      // Overall stats
      int totalRate = 0;
      int lowAttendance = 0;
      int totalRecords = 0;

      for (var student in studentsWithStats) {
        totalRate += student['rate'] as int;
        totalRecords += student['total'] as int;
        if (student['rate'] < 75) {
          lowAttendance++;
        }
      }

      final avgRate = studentsWithStats.isNotEmpty
          ? (totalRate / studentsWithStats.length).round()
          : 0;

      setState(() {
        _classes = classes;
        _students = studentsWithStats;
        _avgAttendance = avgRate;
        _lowAttendanceCount = lowAttendance;
        _totalRecords = totalRecords;
        _loading = false;
      });
    } catch (e) {
      print('Error loading teacher attendance data: $e');
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    var filtered = _students.where((student) {
      final matchesSearch = _searchQuery.isEmpty ||
          student['name']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          student['class']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());

      bool matchesRate = true;
      final rate = student['rate'] as int;
      if (_rateFilter == 'High (>90%)') matchesRate = rate >= 90;
      if (_rateFilter == 'Low (<75%)') matchesRate = rate < 75;
      if (_rateFilter == 'Critical (<50%)') matchesRate = rate < 50;

      return matchesSearch && matchesRate;
    }).toList();

    filtered.sort((a, b) {
      if (_sortBy == 'Rate (High)') {
        return (b['rate'] as int).compareTo(a['rate'] as int);
      }
      if (_sortBy == 'Rate (Low)') {
        return (a['rate'] as int).compareTo(b['rate'] as int);
      }
      return 0;
    });

    return filtered;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2027),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accentColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _filteredStudents;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "My Classes Attendance",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: "Filter by Date Range",
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedDateRange != null) _buildDateChip(),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            "Avg Attendance",
                            '$_avgAttendance%',
                            _avgAttendance >= 80 ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            "Low Attendance",
                            '$_lowAttendanceCount students',
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildFilters(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${filteredList.length} Students',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (_rateFilter != 'All' ||
                            _searchQuery.isNotEmpty ||
                            _selectedDateRange != null ||
                            _selectedClassId != null)
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _rateFilter = 'All';
                                _searchQuery = '';
                                _selectedDateRange = null;
                                _selectedClassId = null;
                              });
                              _loadData();
                            },
                            child: const Text('Clear filters'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filteredList.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          return _buildStudentCard(filteredList[index]);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDateChip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range, color: _accentColor, size: 18),
          const SizedBox(width: 8),
          Text(
            "${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}",
            style: TextStyle(
              color: _accentColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() => _selectedDateRange = null);
              _loadData();
            },
            child: Icon(Icons.close, size: 16, color: _accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or class...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _accentColor, width: 1.5),
            ),
          ),
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
        const SizedBox(height: 12),
        if (_classes.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedClassId,
                isExpanded: true,
                hint: const Text('All Classes'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Classes'),
                  ),
                  ..._classes.map((c) => DropdownMenuItem<String?>(
                        value: c['id'] as String,
                        child: Text(
                          c['name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _selectedClassId = v);
                  _loadData();
                },
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                _rateFilter,
                ['All', 'High (>90%)', 'Low (<75%)', 'Critical (<50%)'],
                (v) => setState(() => _rateFilter = v!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDropdown(
                _sortBy,
                ['Rate (Low)', 'Rate (High)'],
                (v) => setState(() => _sortBy = v!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdown(
      String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: _accentColor),
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final rate = student['rate'] as int;
    Color rateColor =
        rate < 50 ? Colors.red : (rate < 75 ? Colors.orange : Colors.green);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: _accentColor.withOpacity(0.1),
          child: Text(
            student['name'][0].toUpperCase(),
            style: TextStyle(
              color: _accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          student['name'],
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          student['class'],
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: rateColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: rateColor.withOpacity(0.3)),
          ),
          child: Text(
            '$rate%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: rateColor,
            ),
          ),
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDetailStat('Present', '${student['present']}', Colors.green),
              _buildDetailStat('Absent', '${student['absent']}', Colors.red),
              _buildDetailStat('Excused', '${student['excused']}', Colors.orange),
              _buildDetailStat('Total', '${student['total']}', Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

