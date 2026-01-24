import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class AttendanceReportPage extends StatefulWidget {
  const AttendanceReportPage({super.key});

  @override
  State<AttendanceReportPage> createState() => _AttendanceReportPageState();
}

class _AttendanceReportPageState extends State<AttendanceReportPage> {
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
  List<AttendanceRecord> _allRecords = [];
  Map<String, int> _chartData = {};
  String _chartPeriod = 'Daily'; // 'Daily', 'Weekly', 'Monthly'

  // Stats
  int _avgAttendance = 0;
  int _lowAttendanceCount = 0;
  int _totalRecords = 0;
  
  // Tracking breakdown
  int _studentTakenCount = 0;
  int _teacherTakenCount = 0;
  int _presentCount = 0;
  int _absentCount = 0;
  int _excusedCount = 0;

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
      // Load all classes
      final classesSnapshot = await _db.collection('classrooms').get();
      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': '${data['subject'] ?? ''} - ${data['className'] ?? ''}',
        };
      }).toList();

      // Load all students
      final studentsSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();

      List<Map<String, dynamic>> studentsWithStats = [];

      for (var studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final studentId = studentDoc.id;
        final classIds = List<String>.from(studentData['classIds'] ?? []);

        // If class filter is selected, only include students in that class
        if (_selectedClassId != null && !classIds.contains(_selectedClassId)) {
          continue;
        }

        // Get attendance records for this student
        QuerySnapshot<Map<String, dynamic>> recordsSnapshot;
        
        if (_selectedClassId != null) {
          // Filter by specific class
          recordsSnapshot = await _db
              .collection('attendance_records')
              .where('studentId', isEqualTo: studentId)
              .where('classId', isEqualTo: _selectedClassId)
              .get();
        } else {
          // Get all records for this student
          recordsSnapshot = await _db
              .collection('attendance_records')
              .where('studentId', isEqualTo: studentId)
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
            final timestamp = (recordData['timestamp'] as Timestamp?)?.toDate();
            if (timestamp != null) {
              if (timestamp.isBefore(_selectedDateRange!.start) ||
                  timestamp.isAfter(_selectedDateRange!.end.add(const Duration(days: 1)))) {
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
        final rate = total > 0 ? (((present + excused) / total) * 100).round() : 0;

        // Get class names
        List<String> classNames = [];
        for (var classId in classIds) {
          final classMatch = classes.firstWhere(
            (c) => c['id'] == classId,
            orElse: () => {'name': 'Unknown'},
          );
          classNames.add(classMatch['name'] as String);
        }

        // For class filter, show the selected class name
        String displayClass = classNames.isNotEmpty ? classNames.first : 'No class';
        if (_selectedClassId != null) {
          final selectedClassMatch = classes.firstWhere(
            (c) => c['id'] == _selectedClassId,
            orElse: () => {'name': 'Unknown'},
          );
          displayClass = selectedClassMatch['name'] as String;
        }

        studentsWithStats.add({
          'id': studentId,
          'name': studentData['displayName'] ?? 'Unknown Student',
          'email': studentData['email'] ?? '',
          'class': displayClass,
          'classes': classNames,
          'classIds': classIds,
          'rate': rate,
          'present': present,
          'absent': absent,
          'excused': excused,
          'total': total,
        });
      }

      // Calculate overall stats
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

      // Load ALL attendance records for tracking breakdown and charts
      final allRecordsSnapshot = await _db.collection('attendance_records').get();
      final allRecords = allRecordsSnapshot.docs
          .map((doc) => AttendanceRecord.fromMap(doc.id, doc.data()))
          .toList();
      
      // Tracking breakdown
      int studentTaken = 0;
      int teacherTaken = 0;
      int presentTotal = 0;
      int absentTotal = 0;
      int excusedTotal = 0;
      
      for (var record in allRecords) {
        final takenBy = record.takenBy;
        final status = record.status;
        
        if (takenBy == 'teacher') {
          teacherTaken++;
        } else {
          studentTaken++;
        }
        
        if (status == 'present') {
          presentTotal++;
        } else if (status == 'excused') {
          excusedTotal++;
        } else {
          absentTotal++;
        }
      }

      // Load chart data based on period (Malaysia time)
      _allRecords = allRecords;
      final chartData = _loadChartData();

      setState(() {
        _students = studentsWithStats;
        _classes = classes;
        _avgAttendance = avgRate;
        _lowAttendanceCount = lowAttendance;
        _totalRecords = totalRecords;
        _allRecords = allRecords;
        _chartData = chartData;
        _studentTakenCount = studentTaken;
        _teacherTakenCount = teacherTaken;
        _presentCount = presentTotal;
        _absentCount = absentTotal;
        _excusedCount = excusedTotal;
        _loading = false;
      });
    } catch (e) {
      print('Error loading attendance data: $e');
      setState(() => _loading = false);
    }
  }

  Map<String, int> _loadChartData() {
    if (_allRecords.isEmpty) return {};

    final now = TimezoneHelper.getMalaysiaTime();
    final startOfToday =
        TimezoneHelper.createMalaysiaDateTime(now.year, now.month, now.day, 0, 0);

    Map<String, int> chartData = {};

    if (_chartPeriod == 'Daily') {
      // Last 7 days
      for (int i = 6; i >= 0; i--) {
        final dayStart = startOfToday.subtract(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        final labelDate = TimezoneHelper.toMalaysiaTime(dayStart);
        final dayKey = DateFormat('EEE').format(labelDate);

        chartData[dayKey] = _calculateAttendanceRate(dayStart, dayEnd);
      }
    } else if (_chartPeriod == 'Weekly') {
      // Last 4 weeks
      for (int i = 3; i >= 0; i--) {
        final weekStart = startOfToday.subtract(Duration(days: (i * 7) + 6));
        final weekEnd = startOfToday
            .subtract(Duration(days: i * 7))
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
        final weekKey = 'Wk${4 - i}';

        chartData[weekKey] = _calculateAttendanceRate(weekStart, weekEnd);
      }
    } else {
      // Monthly - Last 6 months
      for (int i = 5; i >= 0; i--) {
        final monthStart =
            TimezoneHelper.createMalaysiaDateTime(now.year, now.month - i, 1, 0, 0);
        final monthEnd = TimezoneHelper.createMalaysiaDateTime(
                now.year, now.month - i + 1, 1, 0, 0)
            .subtract(const Duration(seconds: 1));
        final labelDate = TimezoneHelper.toMalaysiaTime(monthStart);
        final monthKey = DateFormat('MMM').format(labelDate);

        chartData[monthKey] = _calculateAttendanceRate(monthStart, monthEnd);
      }
    }

    return chartData;
  }

  int _calculateAttendanceRate(DateTime start, DateTime end) {
    int presentCount = 0;
    int totalCount = 0;

    for (var record in _allRecords) {
      final malaysiaTime = TimezoneHelper.toMalaysiaTime(record.timestamp);
      if (malaysiaTime.isBefore(start) || malaysiaTime.isAfter(end)) {
        continue;
      }
      totalCount++;
      if (record.status == 'present' || record.status == 'excused') {
        presentCount++;
      }
    }

    return totalCount > 0 ? ((presentCount / totalCount) * 100).round() : 0;
  }

  void _changeChartPeriod(String period) {
    setState(() {
      _chartPeriod = period;
      _chartData = _loadChartData();
    });
  }

  List<Map<String, dynamic>> get _filteredStudents {
    var filtered = _students.where((student) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          student['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          student['class'].toString().toLowerCase().contains(_searchQuery.toLowerCase());

      // Rate filter
      bool matchesRate = true;
      final rate = student['rate'] as int;
      if (_rateFilter == 'High (>90%)') matchesRate = rate >= 90;
      if (_rateFilter == 'Low (<75%)') matchesRate = rate < 75;
      if (_rateFilter == 'Critical (<50%)') matchesRate = rate < 50;

      return matchesSearch && matchesRate;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      if (_sortBy == 'Rate (High)') return (b['rate'] as int).compareTo(a['rate'] as int);
      if (_sortBy == 'Rate (Low)') return (a['rate'] as int).compareTo(b['rate'] as int);
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
      _loadData(); // Reload with date filter
    }
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document();
    final now = TimezoneHelper.toMalaysiaTime(DateTime.now());
    final filtered = _filteredStudents;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text("Attendance Report",
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
                "Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(now)}"),
            pw.Divider(),
            pw.SizedBox(height: 20),

            // Summary
            pw.Text("Summary",
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Metric', 'Value'],
              data: [
                ['Average Attendance', '$_avgAttendance%'],
                ['Low Attendance Students', '$_lowAttendanceCount'],
                ['Total Records', '$_totalRecords'],
              ],
            ),
            pw.SizedBox(height: 20),
            
            // Tracking Breakdown
            pw.Text("Attendance Tracking Breakdown",
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Taken By', 'Count'],
              data: [
                ['Student Self Check-in', '$_studentTakenCount'],
                ['Teacher Manual Entry', '$_teacherTakenCount'],
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Status', 'Count'],
              data: [
                ['Present', '$_presentCount'],
                ['Absent', '$_absentCount'],
                ['Excused', '$_excusedCount'],
              ],
            ),
            pw.SizedBox(height: 20),

            // Student List
            pw.Text("Student Attendance (${filtered.length})",
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              context: context,
              headers: ['Name', 'Class', 'Present', 'Absent', 'Excused', 'Rate'],
              data: filtered.map((s) {
                return [
                  s['name'],
                  s['class'],
                  '${s['present']}',
                  '${s['absent']}',
                  '${s['excused']}',
                  '${s['rate']}%',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'attendance_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _filteredStudents;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Attendance Analytics",
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
                    // Date chip
                    if (_selectedDateRange != null) _buildDateChip(),

                    // Stats Row
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

                    // Attendance Chart with Period Selector
                    _buildAttendanceChart(),
                    const SizedBox(height: 24),
                    
                    // Tracking Breakdown
                    _buildTrackingBreakdown(),
                    const SizedBox(height: 24),

                    // Filters
                    _buildFilters(),
                    const SizedBox(height: 16),

                    // Student List Header
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

                    // Student List
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

  Widget _buildAttendanceChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Attendance Trend",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              // Period selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: ['Daily', 'Weekly', 'Monthly'].map((period) {
                    final isSelected = _chartPeriod == period;
                    return InkWell(
                      onTap: () => _changeChartPeriod(period),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? _accentColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          period,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: _chartData.isEmpty
                ? Center(
                    child: Text(
                      'No data available',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _chartData.entries.map((entry) {
                      final pct = entry.value / 100;
                      return _buildChartBar(entry.key, pct);
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text("Export Attendance Report"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: _accentColor),
                foregroundColor: _accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingBreakdown() {
    final totalTaken = _studentTakenCount + _teacherTakenCount;
    final studentPct = totalTaken > 0 ? (_studentTakenCount / totalTaken * 100).round() : 0;
    final teacherPct = totalTaken > 0 ? (_teacherTakenCount / totalTaken * 100).round() : 0;
    final totalStatus = _presentCount + _absentCount + _excusedCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Attendance Tracking Breakdown",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              Icon(Icons.pie_chart, color: _accentColor.withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 20),
          
          // Who took attendance
          const Text(
            'Taken By',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          _buildBreakdownRow(
            icon: Icons.school,
            label: 'Students (Self Check-in)',
            count: _studentTakenCount,
            percentage: studentPct,
            color: Colors.blue,
          ),
          const SizedBox(height: 10),
          _buildBreakdownRow(
            icon: Icons.person,
            label: 'Teachers (Manual Entry)',
            count: _teacherTakenCount,
            percentage: teacherPct,
            color: Colors.orange,
          ),
          
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          
          // Status breakdown
          const Text(
            'Status Summary',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatusStat('Present', _presentCount, Colors.green, totalStatus),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusStat('Absent', _absentCount, Colors.red, totalStatus),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusStat('Excused', _excusedCount, Colors.orange, totalStatus),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required IconData icon,
    required String label,
    required int count,
    required int percentage,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                '$count records',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$percentage%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusStat(String label, int count, Color color, int total) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$label ($pct%)',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(String label, double pct) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${(pct * 100).toInt()}%',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _accentColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: (120 * pct).clamp(4.0, 120.0),
          width: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_accentColor.withOpacity(0.6), _accentColor],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        // Search
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

        // Class filter dropdown
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

        // Rate & Sort filters
        Row(
          children: [
            Expanded(child: _buildDropdown(_rateFilter, ['All', 'High (>90%)', 'Low (<75%)', 'Critical (<50%)'], (v) => setState(() => _rateFilter = v!))),
            const SizedBox(width: 10),
            Expanded(child: _buildDropdown(_sortBy, ['Rate (Low)', 'Rate (High)'], (v) => setState(() => _sortBy = v!))),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
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
    Color rateColor = rate < 50
        ? Colors.red
        : (rate < 75 ? Colors.orange : Colors.green);

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
