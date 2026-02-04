import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/services/auth_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'admin_user_edit_page.dart';

class AdminUserManagement extends StatefulWidget {
  const AdminUserManagement({super.key});

  @override
  State<AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<AdminUserManagement> {
  final _userService = UserService();
  final _themeColor = const Color(0xff1458a3);

  // --- HELPER: Role Colors ---
  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin': return Colors.redAccent;
      case 'teacher': return Colors.green;
      default: return _themeColor; // Student
    }
  }

  // --- HELPER: Role Icons ---
  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin': return Icons.shield_rounded;
      case 'teacher': return Icons.cast_for_education;
      default: return Icons.school_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
        title: const Text("User Management", style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: _themeColor));
          }

          if (authSnapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _themeColor),
                  const SizedBox(height: 12),
                  const Text('Re-authenticating...'),
                ],
              ),
            );
          }

          return StreamBuilder<List<AppUser>>(
            stream: _userService.streamUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: _themeColor));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              }

              final users = snapshot.data ?? [];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // --- Summary Card ---
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xff1458a3), Color(0xff4a90e2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff1458a3).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Total Users",
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "${users.length}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryRow("Students", users.where((u) => u.role == 'student').length),
                            const SizedBox(height: 4),
                            _buildSummaryRow("Teachers", users.where((u) => u.role == 'teacher').length),
                            const SizedBox(height: 4),
                            _buildSummaryRow("Admins", users.where((u) => u.role == 'admin').length),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                // --- Add User Action Card ---
                InkWell(
                  onTap: () => _showCreateUserModal(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _themeColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_add, color: _themeColor, size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Add New User", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            SizedBox(height: 4),
                            Text("Create student, teacher or admin account", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                const Text("All Users", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                // --- Users List ---
                if (users.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text("No users found", style: TextStyle(color: Colors.grey[500], fontSize: 18)),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return _buildUserCard(user);
                    },
                  ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            "$label:",
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          "$count",
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // --- WIDGET: User List Card ---
  Widget _buildUserCard(AppUser user) {
    final roleColor = _getRoleColor(user.role);
    final roleIcon = _getRoleIcon(user.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminUserEditPage(uid: user.uid)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar Area
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    roleIcon,
                    color: roleColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Info Area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Role Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(roleIcon, size: 12, color: roleColor),
                            const SizedBox(width: 4),
                            Text(
                              user.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow Icon
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- MODAL: Create User Form ---
  void _showCreateUserModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
          child: Column(
            children: [
              // Handle Bar
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.person_add_alt_1, color: _themeColor),
                  ),
                  const SizedBox(width: 12),
                  const Text("Create New User", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.grey)),
                ],
              ),
              const Divider(height: 30),

              // Scrollable Form
              Expanded(
                child: CreateUserForm(scrollController: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- SEPARATE WIDGET FOR FORM LOGIC ---
class CreateUserForm extends StatefulWidget {
  final ScrollController scrollController;
  const CreateUserForm({super.key, required this.scrollController});

  @override
  State<CreateUserForm> createState() => _CreateUserFormState();
}

class _CreateUserFormState extends State<CreateUserForm> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _displayName = '';
  String _role = 'student';
  String _adminPassword = '';
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _loading = true);

    try {
      final authService = AuthService();
      const defaultPassword = "password123";

      final result = await authService.adminCreateUser(
        email: _email.trim(),
        password: defaultPassword,
        displayName: _displayName.trim(),
        role: _role,
        adminPassword: _adminPassword.trim(),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => 'Request timed out. Please check your internet connection and try again.',
      );

      if (!mounted) return;

      setState(() => _loading = false);

      if (result == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User created! Default password: password123'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _loading = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating user: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel("Personal Information"),
              _buildInput(
                label: "Full Name",
                icon: Icons.person_outline,
                onSaved: (v) => _displayName = v ?? "",
              ),
              const SizedBox(height: 16),
              _buildInput(
                label: "Email Address",
                icon: Icons.email_outlined,
                inputType: TextInputType.emailAddress,
                onSaved: (v) => _email = v ?? "",
                validator: (v) => v!.contains('@') ? null : "Invalid email",
              ),
              const SizedBox(height: 24),

              _buildLabel("Role Assignment"),
              _buildRoleDropdown(),

              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.vpn_key, size: 20, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(child: Text("Default password will be 'password123'. The user should change this upon login.", style: TextStyle(fontSize: 12, color: Colors.black87))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildLabel("Admin Verification"),
              _buildInput(
                label: "Confirm Your Admin Password",
                icon: Icons.lock_outline,
                isPassword: true,
                onSaved: (v) => _adminPassword = v ?? "",
                validator: (v) => v!.isEmpty ? "Required to prevent logout" : null,
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1458a3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Create User", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1),
      ),
    );
  }

  Widget _buildInput({
    required String label,
    required IconData icon,
    required void Function(String?) onSaved,
    String? Function(String?)? validator,
    bool isPassword = false,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextFormField(
      obscureText: isPassword,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xff1458a3), size: 22),
        filled: true,
        fillColor: const Color(0xffF5F7FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xff1458a3), width: 1.5)),
      ),
      validator: validator ?? (v) => v!.isEmpty ? "Required" : null,
      onSaved: onSaved,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _role,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xff1458a3)),
        filled: true,
        fillColor: const Color(0xffF5F7FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: ['student', 'teacher', 'admin'].map((r) {
        IconData icon;
        Color color;
        switch (r) {
          case 'admin': icon = Icons.shield_rounded; color = Colors.redAccent; break;
          case 'teacher': icon = Icons.cast_for_education; color = Colors.green; break;
          default: icon = Icons.school_outlined; color = const Color(0xff1458a3);
        }
        return DropdownMenuItem(
          value: r,
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              // Use Title Case (capitalize first letter)
              Text(
                  r[0].toUpperCase() + r.substring(1),
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _role = v ?? 'student'),
    );
  }
}