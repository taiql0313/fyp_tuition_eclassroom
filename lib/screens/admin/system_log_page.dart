import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'system_log_detail_page.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class SystemLogPage extends StatefulWidget {
  const SystemLogPage({super.key});

  @override
  State<SystemLogPage> createState() => _SystemLogPageState();
}

class _SystemLogPageState extends State<SystemLogPage> {
  String _filterType = 'All';
  String _filterCategory = 'All';
  String _filterRole = 'All';
  DateTimeRange? _selectedDateRange;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const Color _primaryColor = Color(0xff1458a3);

  final List<String> _categories = const [
    'All',
    'Authentication & Access',
    'Fees & Payment',
    'System Error',
  ];
  final List<String> _roles = const ['All', 'admin', 'teacher', 'student', 'unknown'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _filterType != 'All' ||
      _filterCategory != 'All' ||
      _filterRole != 'All' ||
      _selectedDateRange != null ||
      _searchQuery.isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _filterType = 'All';
      _filterCategory = 'All';
      _filterRole = 'All';
      _selectedDateRange = null;
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "System Logs",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- Filter Section ---
          _buildFilterSection(),

          // --- Log List ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('system_logs')
                  .orderBy('time', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('Failed to load logs', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                final logs = docs
                    .map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final rawCategory = (data['category'] ?? '').toString();
                      if (!_categories.contains(rawCategory)) {
                        return null;
                      }
                      final rawTime =
                          (data['time'] as Timestamp?)?.toDate() ?? DateTime.now();
                      final malaysiaTime = TimezoneHelper.toMalaysiaTime(rawTime);
                      return {
                        'type': data['type'] ?? 'Info',
                        'category': rawCategory,
                        'action': data['action'] ?? 'Log',
                        'user': data['user'] ?? 'Unknown',
                        'userId': data['userId'] ?? '',
                        'role': data['role'] ?? 'unknown',
                        'details': data['details'] ?? '',
                        'ipAddress': data['ipAddress'] ?? '',
                        'device': data['device'] ?? '',
                        'platform': data['platform'] ?? '',
                        'country': data['country'] ?? '',
                        'region': data['region'] ?? '',
                        'city': data['city'] ?? '',
                        'success': data['success'],
                        'time': malaysiaTime,
                      };
                    })
                    .whereType<Map<String, dynamic>>()
                    .toList();

                final filteredLogs = _applyFilters(logs);

                if (filteredLogs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No logs found',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                        if (_hasFilters) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    // Summary bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${filteredLogs.length} logs',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _primaryColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _exportPdf(filteredLogs),
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('Export'),
                            style: TextButton.styleFrom(foregroundColor: _primaryColor),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          return _buildLogCard(filteredLogs[index]);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search logs...',
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
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _primaryColor, width: 1.5),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              _buildDateButton(),
              if (_hasFilters) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off, color: Colors.red),
                  tooltip: 'Clear all filters',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTypeChip('All', Colors.grey),
                const SizedBox(width: 8),
                _buildTypeChip('Info', Colors.blue),
                const SizedBox(width: 8),
                _buildTypeChip('Warning', Colors.orange),
                const SizedBox(width: 8),
                _buildTypeChip('Error', Colors.red),
                const SizedBox(width: 16),
                // Category dropdown (compact)
                _buildCompactDropdown(
                  value: _filterCategory,
                  items: _categories,
                  onChanged: (v) => setState(() => _filterCategory = v ?? 'All'),
                  icon: Icons.category_outlined,
                ),
                const SizedBox(width: 8),
                // Role dropdown (compact)
                _buildCompactDropdown(
                  value: _filterRole,
                  items: _roles,
                  onChanged: (v) => setState(() => _filterRole = v ?? 'All'),
                  icon: Icons.person_outline,
                ),
              ],
            ),
          ),
          if (_selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Chip(
                label: Text(
                  '${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => setState(() => _selectedDateRange = null),
                backgroundColor: _primaryColor.withOpacity(0.1),
                labelStyle: const TextStyle(color: _primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateButton() {
    final hasDate = _selectedDateRange != null;
    return Material(
      color: hasDate ? _primaryColor : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _pickDateRange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range,
                size: 18,
                color: hasDate ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Date',
                style: TextStyle(
                  color: hasDate ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, Color color) {
    final isSelected = _filterType == label;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide.none,
      onSelected: (_) => setState(() => _filterType = label),
    );
  }

  Widget _buildCompactDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            isDense: true,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    Color typeColor;
    IconData typeIcon;

    switch (log['type']) {
      case 'Error':
        typeColor = Colors.red;
        typeIcon = Icons.error_outline;
        break;
      case 'Warning':
        typeColor = Colors.orange;
        typeIcon = Icons.warning_amber_rounded;
        break;
      case 'Info':
      default:
        typeColor = Colors.blue;
        typeIcon = Icons.info_outline;
        break;
    }

    final category = (log['category'] ?? 'System Error') as String;
    final role = (log['role'] ?? 'unknown') as String;
    final success = log['success'];
    final ipAddress = (log['ipAddress'] ?? '') as String;
    final city = (log['city'] ?? '') as String;
    final country = (log['country'] ?? '') as String;
    final hasLocation = city.isNotEmpty || country.isNotEmpty;
    final categoryColor = _categoryColor(category);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openLogDetails(log),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(typeIcon, color: typeColor, size: 22),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log['action'],
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            log['user'],
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildSmallBadge(category, categoryColor),
                        _buildSmallBadge(role, Colors.deepPurple),
                        if (success is bool)
                          _buildSmallBadge(
                            success ? 'Success' : 'Failed',
                            success ? Colors.green : Colors.red,
                          ),
                        if (ipAddress.isNotEmpty)
                          _buildSmallBadge('IP', Colors.blueGrey),
                        if (hasLocation)
                          _buildSmallBadge('Location', Colors.teal),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time & arrow
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('MMM d').format(log['time']),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('h:mm a').format(log['time']),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  void _openLogDetails(Map<String, dynamic> log) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SystemLogDetailPage(log: log),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> logs) {
    return logs.where((log) {
      final type = (log['type'] ?? 'Info') as String;
      final category = (log['category'] ?? 'System Error') as String;
      final role = (log['role'] ?? 'unknown') as String;
      final user = (log['user'] ?? '') as String;
      final userId = (log['userId'] ?? '') as String;
      final action = (log['action'] ?? '') as String;
      final details = (log['details'] ?? '') as String;
      final ipAddress = (log['ipAddress'] ?? '') as String;
      final device = (log['device'] ?? '') as String;
      final platform = (log['platform'] ?? '') as String;
      final city = (log['city'] ?? '') as String;
      final region = (log['region'] ?? '') as String;
      final country = (log['country'] ?? '') as String;
      final time = log['time'] as DateTime;

      if (_filterType != 'All' && type != _filterType) return false;
      if (_filterCategory != 'All' && category != _filterCategory) return false;
      if (_filterRole != 'All' && role != _filterRole) return false;

      if (_selectedDateRange != null) {
        final start = DateTime(
          _selectedDateRange!.start.year,
          _selectedDateRange!.start.month,
          _selectedDateRange!.start.day,
        );
        final end = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
          23,
          59,
          59,
        );
        if (time.isBefore(start) || time.isAfter(end)) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final haystack =
            '$user $userId $action $details $category $role $ipAddress $device $platform $city $region $country'
                .toLowerCase();
        if (!haystack.contains(_searchQuery)) return false;
      }

      return true;
    }).toList();
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Authentication & Access':
        return Colors.indigo;
      case 'Fees & Payment':
        return Colors.green;
      case 'System Error':
      default:
        return Colors.red;
    }
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> logs) async {
    final pdf = pw.Document();
    final headers = ['Time', 'Type', 'Category', 'Action', 'User', 'Role'];
    final data = logs.map((log) {
      return [
        DateFormat('yyyy-MM-dd HH:mm').format(log['time']),
        log['type']?.toString() ?? '',
        log['category']?.toString() ?? '',
        log['action']?.toString() ?? '',
        log['user']?.toString() ?? '',
        log['role']?.toString() ?? '',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('System Logs Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }
}
