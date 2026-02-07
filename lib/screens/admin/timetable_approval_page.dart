import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimetableApprovalPage extends StatefulWidget {
  const TimetableApprovalPage({super.key});

  @override
  State<TimetableApprovalPage> createState() => _TimetableApprovalPageState();
}

class _TimetableApprovalPageState extends State<TimetableApprovalPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Approval'),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('timetables')
            .where('status', isEqualTo: 'pending_approval')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No pending approvals',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All timetable requests have been processed',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          // Sort by lastModified (newest first) on client side
          final pendingTimetables = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              
              Timestamp? aTime;
              Timestamp? bTime;
              
              if (aData['lastModified'] is Timestamp) {
                aTime = aData['lastModified'] as Timestamp;
              } else if (aData['createdAt'] is Timestamp) {
                aTime = aData['createdAt'] as Timestamp;
              }
              
              if (bData['lastModified'] is Timestamp) {
                bTime = bData['lastModified'] as Timestamp;
              } else if (bData['createdAt'] is Timestamp) {
                bTime = bData['createdAt'] as Timestamp;
              }
              
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              
              return bTime.compareTo(aTime); // Descending order
            });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pendingTimetables.length,
            itemBuilder: (context, index) {
              final timetableDoc = pendingTimetables[index];
              final timetableData = timetableDoc.data() as Map<String, dynamic>;
              
              return _buildTimetableCard(
                timetableDoc.id,
                timetableData,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTimetableCard(String timetableId, Map<String, dynamic> timetableData) {
    final classId = timetableData['classId'] as String? ?? '';
    final subjectName = timetableData['subjectName'] as String? ?? 'Unknown Subject';
    final teacherId = timetableData['teacherId'] as String? ?? '';
    
    // Get schedule info
    final baseSchedule = timetableData['baseSchedule'] as Map<String, dynamic>?;
    final pendingChanges = timetableData['pendingChanges'] as Map<String, dynamic>?;
    
    // Use pending changes if available, otherwise use base schedule
    final scheduleToShow = pendingChanges ?? baseSchedule;
    
    final dayOfWeek = scheduleToShow?['dayOfWeek'] as int? ?? 0;
    final startTime = scheduleToShow?['startTime'] as String? ?? '';
    final endTime = scheduleToShow?['endTime'] as String? ?? '';
    
    final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final dayName = dayOfWeek < days.length ? days[dayOfWeek] : 'Unknown';
    
    // Format date
    String dateStr = 'Unknown';
    if (timetableData['lastModified'] is Timestamp) {
      dateStr = DateFormat('MMM d, y h:mm a').format(
        (timetableData['lastModified'] as Timestamp).toDate(),
      );
    } else if (timetableData['createdAt'] is Timestamp) {
      dateStr = DateFormat('MMM d, y h:mm a').format(
        (timetableData['createdAt'] as Timestamp).toDate(),
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(teacherId).get(),
      builder: (context, teacherSnapshot) {
        String teacherName = 'Teacher';
        if (teacherSnapshot.hasData && teacherSnapshot.data!.exists) {
          final teacherData = teacherSnapshot.data!.data() as Map<String, dynamic>?;
          teacherName = teacherData?['displayName'] ?? 'Teacher';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.shade200, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.schedule,
                        color: Colors.orange.shade700,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subjectName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Teacher: $teacherName',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Pending',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),

                // Schedule Details
                const Text(
                  'Requested Schedule:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildScheduleItem(
                      Icons.calendar_today,
                      dayName,
                      Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildScheduleItem(
                      Icons.access_time,
                      '$startTime - $endTime',
                      Colors.green,
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Text(
                  'Submitted: $dateStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 20),
                const Divider(),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectTimetable(timetableId, classId, dayOfWeek, '$startTime-$endTime'),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => _approveTimetable(timetableId, timetableData, classId),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleItem(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveTimetable(
    String timetableId,
    Map<String, dynamic> timetableData,
    String classId,
  ) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    try {
      final timetableRef = FirebaseFirestore.instance
          .collection('timetables')
          .doc(timetableId);

      // Get pending changes or use base schedule
      final pendingChanges = timetableData['pendingChanges'] as Map<String, dynamic>?;
      final baseSchedule = timetableData['baseSchedule'] as Map<String, dynamic>?;
      
      // Use pending changes if available, otherwise keep base schedule
      final scheduleToApply = pendingChanges ?? baseSchedule;

      if (scheduleToApply != null) {
        // Update timetable with approved schedule
        await timetableRef.update({
          'baseSchedule': scheduleToApply,
          'status': 'approved',
          'approvedBy': admin.uid,
          'approvedAt': FieldValue.serverTimestamp(),
          'pendingChanges': FieldValue.delete(),
          'lastModified': FieldValue.serverTimestamp(),
        });

        // Update time locks with timetable ID
        final dayOfWeek = scheduleToApply['dayOfWeek'] as int? ?? 0;
        final timeSlot = '${scheduleToApply['startTime']}-${scheduleToApply['endTime']}';
        
        await _updateTimeLocks(classId, timetableId, dayOfWeek, timeSlot);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Timetable approved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving timetable: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectTimetable(
    String timetableId,
    String classId,
    int dayOfWeek,
    String timeSlot,
  ) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject Timetable Request'),
          content: const Text('Are you sure you want to reject this timetable request? The time slot will be unlocked.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reject'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Update timetable status
      await FirebaseFirestore.instance
          .collection('timetables')
          .doc(timetableId)
          .update({
        'status': 'rejected',
        'rejectedBy': admin.uid,
        'rejectedAt': FieldValue.serverTimestamp(),
        'pendingChanges': FieldValue.delete(),
        'lastModified': FieldValue.serverTimestamp(),
      });

      // Unlock time slots
      await _unlockTimeSlots(classId, dayOfWeek, timeSlot);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timetable request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting timetable: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateTimeLocks(
    String classId,
    String timetableId,
    int dayOfWeek,
    String timeSlot,
  ) async {
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    // Update all time locks for this month
    for (int day = 1; day <= 31; day++) {
      try {
        final date = DateTime(currentYear, currentMonth, day);
        if (date.month != currentMonth) break;

        if (date.weekday == (dayOfWeek == 0 ? 7 : dayOfWeek)) {
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final lockDocRef = FirebaseFirestore.instance
              .collection('timeLocks')
              .doc('$dateStr-$timeSlot');

          final lockDoc = await lockDocRef.get();
          
          if (lockDoc.exists) {
            final currentLocks = lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
            
            // Update timetableId in the lock
            final updatedLocks = currentLocks.map((lock) {
              final lockMap = lock as Map<String, dynamic>;
              if (lockMap['classId'] == classId) {
                return {
                  ...lockMap,
                  'timetableId': timetableId,
                };
              }
              return lock;
            }).toList();

            await lockDocRef.update({
              'lockedBy': updatedLocks,
            });
          }
        }
      } catch (e) {
        continue;
      }
    }
  }

  Future<void> _unlockTimeSlots(
    String classId,
    int dayOfWeek,
    String timeSlot,
  ) async {
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    // Remove locks for this class
    for (int day = 1; day <= 31; day++) {
      try {
        final date = DateTime(currentYear, currentMonth, day);
        if (date.month != currentMonth) break;

        if (date.weekday == (dayOfWeek == 0 ? 7 : dayOfWeek)) {
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          final lockDocRef = FirebaseFirestore.instance
              .collection('timeLocks')
              .doc('$dateStr-$timeSlot');

          final lockDoc = await lockDocRef.get();
          
          if (lockDoc.exists) {
            final currentLocks = lockDoc.data()?['lockedBy'] as List<dynamic>? ?? [];
            
            // Remove locks for this class
            final updatedLocks = currentLocks.where((lock) {
              final lockMap = lock as Map<String, dynamic>;
              return lockMap['classId'] != classId;
            }).toList();

            if (updatedLocks.isEmpty) {
              await lockDocRef.delete();
            } else {
              await lockDocRef.update({
                'lockedBy': updatedLocks,
              });
            }
          }
        }
      } catch (e) {
        continue;
      }
    }
  }
}
