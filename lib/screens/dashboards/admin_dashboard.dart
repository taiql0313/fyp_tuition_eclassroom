import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';

// --- IMPORTS ---
import '../admin/reports/reports_page.dart';
import '../admin/admin_user_management.dart';
import '../admin/system_log_page.dart'; // 👈 NEW IMPORT

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          // --- CUSTOM HEADER ---
          Container(
            padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 30),
            decoration: const BoxDecoration(
              color: Color(0xff1458a3),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Admin Console", style: TextStyle(color: Colors.white70, fontSize: 14)),
                        SizedBox(height: 5),
                        Text("Dashboard", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                      child: IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () async {
                          await auth.signOut();
                          if (context.mounted) Navigator.pushReplacementNamed(context, Routes.login);
                        },
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),

          // --- BODY CONTENT ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text("System Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 15),

                const Row(
                  children: [
                    Expanded(child: _StatCard(label: "Active Users", value: "1,240", color: Colors.blue)),
                    SizedBox(width: 15),
                    Expanded(child: _StatCard(label: "Daily Revenue", value: "RM 4.2k", color: Colors.green)),
                  ],
                ),

                const SizedBox(height: 25),
                const Text("Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
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

                    _adminTile(context, 'Reports', Icons.bar_chart, Colors.orange, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
                    }),

                    _adminTile(context, 'Payments', Icons.receipt_long, Colors.green),

                    // LINKED LOGS PAGE
                    _adminTile(context, 'Logs', Icons.terminal, Colors.blueGrey, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemLogPage()));
                    }),

                    _adminTile(context, 'Settings', Icons.settings_outlined, Colors.grey),
                    _adminTile(context, 'Monitoring', Icons.speed, Colors.redAccent),
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
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? () {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text("Feature Coming Soon")));
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}