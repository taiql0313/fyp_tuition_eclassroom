import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SystemLogPage extends StatefulWidget {
  const SystemLogPage({super.key});

  @override
  State<SystemLogPage> createState() => _SystemLogPageState();
}

class _SystemLogPageState extends State<SystemLogPage> {
  String _filterType = 'All'; // All, Info, Warning, Error

  // Mock Log Data
  final List<Map<String, dynamic>> _logs = [
    {
      'type': 'Error',
      'action': 'Failed Login Attempt',
      'user': 'unknown_ip_882',
      'time': DateTime.now().subtract(const Duration(minutes: 5)),
      'details': 'Invalid password entered 5 times.'
    },
    {
      'type': 'Info',
      'action': 'New User Registered',
      'user': 'Ali Ahmad (Student)',
      'time': DateTime.now().subtract(const Duration(hours: 1)),
      'details': 'Account created successfully.'
    },
    {
      'type': 'Warning',
      'action': 'Payment Overdue Alert',
      'user': 'System Bot',
      'time': DateTime.now().subtract(const Duration(hours: 3)),
      'details': 'Sent reminder emails to 15 students.'
    },
    {
      'type': 'Info',
      'action': 'Attendance Session Closed',
      'user': 'Mr. Tan (Teacher)',
      'time': DateTime.now().subtract(const Duration(days: 1)),
      'details': 'Class 5A Mathematics session ended.'
    },
    {
      'type': 'Error',
      'action': 'Database Connection Timeout',
      'user': 'System',
      'time': DateTime.now().subtract(const Duration(days: 2)),
      'details': 'Firestore read operation timed out.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xff1458a3);

    // Filter Logic
    final filteredLogs = _filterType == 'All'
        ? _logs
        : _logs.where((log) => log['type'] == _filterType).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("System Logs"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: "Clear Logs",
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Logs cleared (Mock Action)")),
              );
              setState(() {
                // In a real app, this would clear the list or database
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          // --- Filter Section ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFilterChip('All', Colors.grey),
                _buildFilterChip('Info', Colors.blue),
                _buildFilterChip('Warning', Colors.orange),
                _buildFilterChip('Error', Colors.red),
              ],
            ),
          ),

          // --- Log List ---
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filteredLogs.length,
              separatorBuilder: (c, i) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final log = filteredLogs[index];
                return _buildLogCard(log);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, Color color) {
    final isSelected = _filterType == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _filterType = label;
        });
      },
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey[100],
      side: isSelected ? BorderSide(color: color) : BorderSide.none,
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    Color color;
    IconData icon;

    switch (log['type']) {
      case 'Error':
        color = Colors.red;
        icon = Icons.error_outline;
        break;
      case 'Warning':
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        break;
      case 'Info':
      default:
        color = Colors.blue;
        icon = Icons.info_outline;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          log['action'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                log['user'],
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, h:mm a').format(log['time']),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Details: ${log['details']}",
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          )
        ],
      ),
    );
  }
}