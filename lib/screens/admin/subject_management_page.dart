import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/services/subject_service.dart';
import 'package:fyp_tuition_eclassroom/models/subject_model.dart';

class SubjectManagementPage extends StatefulWidget {
  const SubjectManagementPage({super.key});

  @override
  State<SubjectManagementPage> createState() => _SubjectManagementPageState();
}

class _SubjectManagementPageState extends State<SubjectManagementPage> {
  final SubjectService _subjectService = SubjectService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  Subject? _editingSubject;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    _nameController.clear();
    _priceController.clear();
    _editingSubject = null;

    showDialog(
      context: context,
      builder: (context) => _SubjectDialog(
        nameController: _nameController,
        priceController: _priceController,
        subjectService: _subjectService,
        editingSubject: null,
        onSuccess: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Subject created successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _showEditDialog(Subject subject) {
    _nameController.text = subject.name;
    _priceController.text = subject.price.toStringAsFixed(2);
    _editingSubject = subject;

    showDialog(
      context: context,
      builder: (context) => _SubjectDialog(
        nameController: _nameController,
        priceController: _priceController,
        subjectService: _subjectService,
        editingSubject: subject,
        onSuccess: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Subject updated successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteSubject(Subject subject) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Subject"),
        content: Text("Are you sure you want to delete '${subject.name}'? This will deactivate the subject."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _subjectService.deleteSubject(subject.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Subject deleted successfully"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: ${e.toString()}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Subject Management"),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header with Create Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Manage Subjects",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text("Create Subject"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1458a3),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Subjects List
          Expanded(
            child: StreamBuilder<List<Subject>>(
              stream: _subjectService.streamAllSubjects(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.book_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "No subjects found",
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Click 'Create Subject' to add one",
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                final subjects = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: subjects.length,
                  itemBuilder: (context, index) {
                    final subject = subjects[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: subject.isActive
                                ? const Color(0xff1458a3).withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.book,
                            color: subject.isActive
                                ? const Color(0xff1458a3)
                                : Colors.grey,
                          ),
                        ),
                        title: Text(
                          subject.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: subject.isActive
                                ? null
                                : TextDecoration.lineThrough,
                            color: subject.isActive
                                ? Colors.black
                                : Colors.grey,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              "Price: RM ${NumberFormat('#,##0.00').format(subject.price)}",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Created: ${DateFormat('MMM d, yyyy').format(subject.createdAt)}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            if (!subject.isActive)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Inactive",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showEditDialog(subject),
                              tooltip: "Edit",
                            ),
                            if (subject.isActive)
                              IconButton(
                                icon: const Icon(Icons.block, color: Colors.red),
                                onPressed: () => _deleteSubject(subject),
                                tooltip: "Mark Inactive",
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.green),
                                onPressed: () async {
                                  try {
                                    await _subjectService.updateSubject(
                                      subjectId: subject.id,
                                      isActive: true,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("'${subject.name}' reactivated successfully"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Error: ${e.toString()}"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                tooltip: "Activate",
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectDialog extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final SubjectService subjectService;
  final Subject? editingSubject;
  final VoidCallback onSuccess;

  const _SubjectDialog({
    required this.nameController,
    required this.priceController,
    required this.subjectService,
    this.editingSubject,
    required this.onSuccess,
  });

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editingSubject != null;

    return AlertDialog(
      title: Text(isEditing ? "Edit Subject" : "Create Subject"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.nameController,
            decoration: const InputDecoration(
              labelText: "Subject Name",
              hintText: "e.g., Physics",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.book),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Price (RM)",
              hintText: "e.g., 150.00",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
              prefixText: "RM ",
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSubmit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? "Update" : "Create"),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (widget.nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter subject name")),
      );
      return;
    }

    final price = double.tryParse(widget.priceController.text);
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid price")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.editingSubject != null) {
        // Update existing subject
        await widget.subjectService.updateSubject(
          subjectId: widget.editingSubject!.id,
          name: widget.nameController.text.trim(),
          price: price,
        );
      } else {
        // Create new subject
        await widget.subjectService.createSubject(
          name: widget.nameController.text.trim(),
          price: price,
        );
      }

      if (context.mounted) {
        widget.onSuccess();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
