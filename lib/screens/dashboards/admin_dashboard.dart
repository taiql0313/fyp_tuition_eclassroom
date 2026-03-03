import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';

// --- IMPORTS ---
import '../admin/reports/reports_page.dart';
import '../admin/admin_user_management.dart';
import '../admin/system_log_page.dart';
import '../admin/timetable_approval_page.dart';
import '../admin/absence_approval_page.dart';
import '../admin/subject_management_page.dart';
import '../admin/payment_management_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    final theme = Theme.of(context);
    final appBarColor = theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 20),
            decoration: BoxDecoration(
              color: appBarColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'e',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Admin Console",
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "System Administrator",
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_none, color: Colors.white),
                              onPressed: () {},
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onSelected: (value) async {
                            if (value == 'settings') {
                              Navigator.pushNamed(context, Routes.settings);
                            } else if (value == 'logout') {
                              await auth.signOut();
                              if (context.mounted) Navigator.pushReplacementNamed(context, Routes.login);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'settings', child: Text('Settings')),
                            const PopupMenuItem(
                              value: 'logout',
                              child: Text('Logout', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- WELCOME BACK CARD ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: _WelcomeBackCard(auth: auth),
          ),

          // --- BODY CONTENT ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text("System Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 15),

                Row(
                  children: [
                    Expanded(child: _UsersStatCard()),
                    const SizedBox(width: 15),
                    Expanded(child: _DailyRevenueStatCard()),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _TotalCoursesStatCard()),
                    const SizedBox(width: 15),
                    // System Health card removed as per user request
                    const Expanded(child: SizedBox()),
                  ],
                ),

                const SizedBox(height: 25),
                Text("Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 15),

                // Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.3,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  children: [
                    _adminTile(context, 'Manage Users', Icons.group_outlined, Colors.indigo, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUserManagement()));
                    }),

                    _adminTile(context, 'Manage Subjects', Icons.book_outlined, Colors.purple, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectManagementPage()));
                    }),

                    _adminTile(context, 'Reports', Icons.bar_chart, Colors.orange, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
                    }),

                    _adminTile(context, 'Payment Management', Icons.receipt_long, Colors.green, onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentManagementPage(),
                        ),
                      );
                    }),

                    // LINKED LOGS PAGE
                    _adminTile(context, 'Logs', Icons.terminal, Colors.blueGrey, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemLogPage()));
                    }),

                    _adminTile(context, 'Settings', Icons.settings_outlined, Colors.grey),
                    _adminTile(context, 'Monitoring', Icons.speed, Colors.redAccent),

                    // TIMETABLE APPROVAL TILE with badge
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('timetables')
                          .where('status', isEqualTo: 'pending_approval')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final pendingCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                        return _adminTileWithBadge(
                          context,
                          'Timetable Approval',
                          Icons.schedule_outlined,
                          Colors.teal,
                          pendingCount,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TimetableApprovalPage(),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    // ABSENCE DOCUMENT APPROVAL TILE with badge
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('absence_documents')
                          .where('status', isEqualTo: 'pending')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final pendingCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                        return _adminTileWithBadge(
                          context,
                          'Absence Approval',
                          Icons.description_outlined,
                          Colors.orange,
                          pendingCount,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AbsenceApprovalPage(),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminTile(BuildContext c, String title, IconData icon, Color color, {VoidCallback? onTap}) {
    final theme = Theme.of(c);
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? () {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text("Feature Coming Soon")));
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminTileWithBadge(
    BuildContext c,
    String title,
    IconData icon,
    Color color,
    int badgeCount, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(c);
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? () {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text("Feature Coming Soon")));
        },
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            if (badgeCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Base Stat Card Widget
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Users Stat Card with Real Data
class _UsersStatCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        final userCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        final formattedCount = _formatNumber(userCount);
        
        return _StatCard(
          label: "Users",
          value: formattedCount,
          icon: Icons.people_outline,
          color: Colors.blue,
        );
      },
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}

// Daily Revenue Stat Card with Real Data
class _DailyRevenueStatCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payment_transactions')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('completedAt', isLessThan: Timestamp.fromDate(endOfDay))
          .snapshots(),
      builder: (context, snapshot) {
        double totalRevenue = 0.0;
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            totalRevenue += amount;
          }
        }

        final formattedRevenue = _formatCurrency(totalRevenue);
        
        return _StatCard(
          label: "Daily Revenue",
          value: formattedRevenue,
          icon: Icons.attach_money,
          color: Colors.green,
        );
      },
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000) {
      return 'RM ${(amount / 1000).toStringAsFixed(1)}k';
    }
    return 'RM ${amount.toStringAsFixed(0)}';
  }
}

// Total Courses Stat Card with Real Data
class _TotalCoursesStatCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('classrooms').snapshots(),
      builder: (context, snapshot) {
        final courseCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        
        return _StatCard(
          label: "Total Courses",
          value: courseCount.toString(),
          icon: Icons.book_outlined,
          color: Colors.purple,
        );
      },
    );
  }
}

// Welcome Back Card Widget
class _WelcomeBackCard extends StatelessWidget {
  final AuthService auth;
  
  const _WelcomeBackCard({required this.auth});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final uid = user?.uid ?? "";

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        String displayName = user?.displayName ?? "Admin Manager";
        String lastLoginText = "Last login: Today, ${DateFormat('h:mm a').format(DateTime.now())}";

        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          displayName = userData?['displayName'] ?? user?.displayName ?? "Admin Manager";
          
          // Get last login time from Firestore
          final lastLogin = userData?['lastLogin'] as Timestamp?;
          if (lastLogin != null) {
            final lastLoginDate = lastLogin.toDate();
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final loginDay = DateTime(lastLoginDate.year, lastLoginDate.month, lastLoginDate.day);
            
            if (loginDay == today) {
              lastLoginText = "Last login: Today, ${DateFormat('h:mm a').format(lastLoginDate)}";
            } else {
              final yesterday = today.subtract(const Duration(days: 1));
              if (loginDay == yesterday) {
                lastLoginText = "Last login: Yesterday, ${DateFormat('h:mm a').format(lastLoginDate)}";
              } else {
                lastLoginText = "Last login: ${DateFormat('MMM d, y').format(lastLoginDate)}, ${DateFormat('h:mm a').format(lastLoginDate)}";
              }
            }
          }
        }

        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardTheme.color ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_outlined, color: primary, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Welcome back,",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayName,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastLoginText,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, color: primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "Admin",
                      style: TextStyle(
                        color: primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}