import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherNotificationCenterPage extends StatefulWidget {
  const TeacherNotificationCenterPage({super.key});

  @override
  State<TeacherNotificationCenterPage> createState() => _TeacherNotificationCenterPageState();
}

class _TeacherNotificationCenterPageState extends State<TeacherNotificationCenterPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _markAllAsRead(String userId) async {
    final snapshot = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['read'] != true) {
        batch.update(doc.reference, {'read': true});
      }
    }
    await batch.commit();
  }

  Future<void> _markAsRead(DocumentReference ref, Map<String, dynamic> data) async {
    if (data['read'] == true) return;
    await ref.update({'read': true});
  }

  DateTime _getTimestamp(Map<String, dynamic> data) {
    final ts = data['timestamp'] ?? data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_outline;
      case 'timetable':
        return Icons.schedule_outlined;
      case 'assignment':
        return Icons.assignment_turned_in_outlined;
      case 'attendance':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'message':
        return Colors.blue;
      case 'timetable':
        return Colors.teal;
      case 'assignment':
        return Colors.green;
      case 'attendance':
        return Colors.orange;
      default:
        return const Color(0xFF1458A3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view notifications.')),
      );
    }

    final notificationsStream = _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots();

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: notificationsStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final unreadCount = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['read'] != true;
              }).length;
              if (unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _markAllAsRead(user.uid),
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          final notifications = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              'ref': doc.reference,
              'data': data,
            };
          }).toList();

          notifications.sort((a, b) {
            final aTime = _getTimestamp(a['data'] as Map<String, dynamic>);
            final bTime = _getTimestamp(b['data'] as Map<String, dynamic>);
            return bTime.compareTo(aTime);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = notifications[index];
              final data = item['data'] as Map<String, dynamic>;
              final ref = item['ref'] as DocumentReference;
              final isRead = data['read'] == true;
              final title = data['title']?.toString() ?? 'Notification';
              final message = data['message']?.toString() ?? '';
              final type = data['type']?.toString() ?? 'general';
              final timestamp = _getTimestamp(data);
              final formattedTime = DateFormat('dd MMM, hh:mm a').format(timestamp);
              final iconColor = _colorForType(type);

              return InkWell(
                onTap: () => _markAsRead(ref, data),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead 
                        ? (theme.cardTheme.color ?? theme.colorScheme.surface)
                        : iconColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isRead ? theme.dividerColor : iconColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isRead ? Colors.grey.shade200 : iconColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconForType(type), color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              formattedTime,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8, top: 6),
                          decoration: BoxDecoration(
                            color: iconColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
