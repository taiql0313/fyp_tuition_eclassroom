import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SystemLogDetailPage extends StatelessWidget {
  final Map<String, dynamic> log;

  const SystemLogDetailPage({super.key, required this.log});

  static const Color _primaryColor = Color(0xff1458a3);

  @override
  Widget build(BuildContext context) {
    final category = (log['category'] ?? 'System Error') as String;
    final role = (log['role'] ?? 'unknown') as String;
    final success = log['success'];
    final time = log['time'] as DateTime;
    final ipAddress = (log['ipAddress'] ?? '') as String;
    final device = (log['device'] ?? '') as String;
    final platform = (log['platform'] ?? '') as String;
    final city = (log['city'] ?? '') as String;
    final region = (log['region'] ?? '') as String;
    final country = (log['country'] ?? '') as String;
    final type = (log['type'] ?? 'Info') as String;

    Color typeColor;
    IconData typeIcon;
    switch (type) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Log Details',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card with action and type
            _buildHeaderCard(typeColor, typeIcon, type, success),
            const SizedBox(height: 16),

            // User & Time Info
            _buildSection(
              icon: Icons.person_outline,
              iconColor: Colors.deepPurple,
              title: 'User Information',
              children: [
                _detailRow('User', log['user'] ?? 'Unknown'),
                _detailRow('Role', _capitalize(role)),
                _detailRow('Category', category),
              ],
            ),
            const SizedBox(height: 12),

            // Time Info
            _buildSection(
              icon: Icons.access_time,
              iconColor: Colors.teal,
              title: 'Timestamp',
              children: [
                _detailRow('Date', DateFormat('EEEE, MMMM d, yyyy').format(time)),
                _detailRow('Time', DateFormat('h:mm:ss a').format(time)),
              ],
            ),
            const SizedBox(height: 12),

            // Device & IP Info
            _buildSection(
              icon: Icons.devices,
              iconColor: Colors.indigo,
              title: 'Device & IP Address',
              children: [
                _detailRowWithIcon(
                  'IP Address',
                  ipAddress.isNotEmpty ? ipAddress : 'Not available',
                  Icons.language,
                  ipAddress.isNotEmpty,
                ),
                _detailRowWithIcon(
                  'Device',
                  device.isNotEmpty ? device : (platform.isNotEmpty ? platform : 'Not available'),
                  Icons.phone_android,
                  device.isNotEmpty || platform.isNotEmpty,
                ),
                _detailRowWithIcon(
                  'Platform',
                  platform.isNotEmpty ? platform : 'Not available',
                  Icons.computer,
                  platform.isNotEmpty,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Location Info
            _buildSection(
              icon: Icons.location_on_outlined,
              iconColor: Colors.green,
              title: 'Location',
              children: [
                _detailRowWithIcon(
                  'Country',
                  country.isNotEmpty ? country : 'Not available',
                  Icons.flag_outlined,
                  country.isNotEmpty,
                ),
                _detailRowWithIcon(
                  'Region',
                  region.isNotEmpty ? region : 'Not available',
                  Icons.map_outlined,
                  region.isNotEmpty,
                ),
                _detailRowWithIcon(
                  'City',
                  city.isNotEmpty ? city : 'Not available',
                  Icons.location_city,
                  city.isNotEmpty,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Details
            _buildSection(
              icon: Icons.description_outlined,
              iconColor: Colors.grey,
              title: 'Details',
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    (log['details'] ?? '').toString().isNotEmpty
                        ? log['details']
                        : 'No additional details',
                    style: TextStyle(
                      fontSize: 13,
                      color: (log['details'] ?? '').toString().isNotEmpty
                          ? Colors.black87
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(Color typeColor, IconData typeIcon, String type, dynamic success) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: typeColor.withOpacity(0.3)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              typeColor.withOpacity(0.05),
              typeColor.withOpacity(0.02),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log['action'] ?? 'Log Entry',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildTypeBadge(type, typeColor),
                          const SizedBox(width: 8),
                          if (success is bool) _buildStatusBadge(success),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool success) {
    final color = success ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            success ? 'SUCCESS' : 'FAILED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRowWithIcon(String label, String value, IconData icon, bool hasValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: hasValue ? _primaryColor : Colors.grey.shade400,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                fontSize: 13,
                color: hasValue ? Colors.black87 : Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
