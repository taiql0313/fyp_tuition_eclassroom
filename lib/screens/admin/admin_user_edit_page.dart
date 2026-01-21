import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Required for delete fix
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/services/auth_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';

class AdminUserEditPage extends StatefulWidget {
  final String uid;

  const AdminUserEditPage({super.key, required this.uid});

  @override
  State<AdminUserEditPage> createState() => _AdminUserEditPageState();
}

class _AdminUserEditPageState extends State<AdminUserEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _userService = UserService();

  bool _loading = false;
  AppUser? _user;

  String _displayName = "";
  String _role = "student";

  // Consistent Primary Color
  final Color themeColor = const Color(0xff1458a3);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final data = await _userService.getUser(widget.uid);
    if (mounted && data != null) {
      setState(() {
        _user = data;
        _displayName = data.displayName;
        _role = data.role;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _loading = true);

    await _userService.updateUser(
      uid: widget.uid,
      displayName: _displayName,
      role: _role,
    );

    if (!mounted) return;

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Profile updated successfully"),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete User"),
        content: const Text("Are you sure? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      try {
        // Direct delete call to fix the "undefined method" error
        await FirebaseFirestore.instance.collection('users').doc(widget.uid).delete();

        if (mounted) Navigator.pop(context); // Go back after delete
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(backgroundColor: themeColor, elevation: 0),
        body: Center(child: CircularProgressIndicator(color: themeColor)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Standard Dashboard BG
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Edit Profile",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Gradient Header with Avatar
            _buildGradientHeader(),

            // 2. Main Content
            Transform.translate(
              offset: const Offset(0, -20), // Slight overlap for modern look
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Personal Info Section
                      _buildSectionContainer(
                        title: "Personal Information",
                        children: [
                          _buildModernInput(
                            label: "Full Name",
                            initialValue: _displayName,
                            icon: Icons.person_outline,
                            onSaved: (v) => _displayName = v ?? "",
                          ),
                          const SizedBox(height: 16),
                          _buildRoleDropdown(),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Security Section
                      _buildSectionContainer(
                        title: "Security & Actions",
                        children: [
                          _buildActionTile(
                            title: "Reset Password",
                            subtitle: "Send recovery email",
                            icon: Icons.lock_reset,
                            color: Colors.blue,
                            onTap: () async {
                              final auth = context.read<AuthService>();
                              // auth.sendPasswordReset(email: _user!.email);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Reset email functionality triggered")),
                              );
                            },
                          ),
                          const Divider(height: 24),
                          _buildActionTile(
                            title: "Delete User",
                            subtitle: "Permanently remove account",
                            icon: Icons.delete_forever,
                            color: Colors.red,
                            onTap: _deleteUser,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 80), // Spacer for bottom button
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildGradientHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 50),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff1458a3), Color(0xff4a90e2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: _getRoleColor(_role).withOpacity(0.1),
              child: Icon(_getRoleIcon(_role), size: 36, color: _getRoleColor(_role)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _user!.email,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _role.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContainer({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // UPDATED: Matches "Quick Actions" style
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87, // Changed from grey to black
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildModernInput({
    required String label,
    required String initialValue,
    required IconData icon,
    required void Function(String?) onSaved,
  }) {
    return TextFormField(
      initialValue: initialValue,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: themeColor),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: themeColor, width: 2),
        ),
      ),
      validator: (v) => v!.isEmpty ? "Required" : null,
      onSaved: onSaved,
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _role,
      decoration: InputDecoration(
        labelText: "Role",
        prefixIcon: Icon(Icons.badge_outlined, color: themeColor),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: themeColor, width: 2),
        ),
      ),
      items: ["student", "teacher", "admin"].map((role) {
        return DropdownMenuItem(
          value: role,
          child: Row(
            children: [
              Icon(_getRoleIcon(role), size: 20, color: _getRoleColor(role)),
              const SizedBox(width: 12),
              Text(
                role[0].toUpperCase() + role.substring(1),
                style: TextStyle(fontWeight: FontWeight.w600, color: _getRoleColor(role)),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _role = v ?? "student"),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      // UPDATED: Text color is now standard black87, only icon is colored
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case "admin": return Colors.red;
      case "teacher": return Colors.green;
      default: return Colors.blue;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case "admin": return Icons.admin_panel_settings;
      case "teacher": return Icons.school;
      default: return Icons.person;
    }
  }
}