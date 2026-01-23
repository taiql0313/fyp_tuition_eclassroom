import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/services/payment_service.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';

class PaymentRemindersPage extends StatefulWidget {
  const PaymentRemindersPage({super.key});

  @override
  State<PaymentRemindersPage> createState() => _PaymentRemindersPageState();
}

class _PaymentRemindersPageState extends State<PaymentRemindersPage> with SingleTickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Automatically check for new reminders when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRemindersOnLoad();
    });
  }

  Future<void> _checkRemindersOnLoad() async {
    try {
      await _paymentService.checkAndSendReminders();
    } catch (e) {
      print('Error checking reminders on load: $e');
      // Don't show error to user on initial load, just log it
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment Reminders"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Pending Reminders", icon: Icon(Icons.notifications_active)),
            Tab(text: "Reminder History", icon: Icon(Icons.history)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Check for New Reminders",
            onPressed: () async {
              try {
                await _paymentService.checkAndSendReminders();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Reminder check completed!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Error: ${e.toString()}"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRemindersTab(),
          _buildReminderHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildPendingRemindersTab() {
    return StreamBuilder<List<PaymentReminder>>(
      stream: _paymentService.streamPaymentReminders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  "No reminders found",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final reminders = snapshot.data!
            .where((r) => !r.sent)
            .toList();

        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green[400]),
                const SizedBox(height: 16),
                Text(
                  "All reminders have been sent",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reminders.length,
          itemBuilder: (context, index) {
            return _buildReminderCard(reminders[index], isPending: true);
          },
        );
      },
    );
  }

  Widget _buildReminderHistoryTab() {
    return StreamBuilder<List<PaymentReminder>>(
      stream: _paymentService.streamPaymentReminders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  "No reminder history",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final reminders = snapshot.data!
            .where((r) => r.sent)
            .toList();

        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  "No sent reminders yet",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reminders.length,
          itemBuilder: (context, index) {
            return _buildReminderCard(reminders[index], isPending: false);
          },
        );
      },
    );
  }

  Widget _buildReminderCard(PaymentReminder reminder, {required bool isPending}) {
    final typeColor = reminder.reminderType == 'overdue'
        ? Colors.red
        : reminder.reminderType == 'after_due_date'
            ? Colors.orange
            : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: typeColor.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPending ? Icons.notifications_active : Icons.check_circle,
            color: typeColor,
          ),
        ),
        title: Text(
          reminder.studentName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _getReminderTypeText(reminder.reminderType),
              style: TextStyle(color: typeColor.shade700, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            // For pending reminders, show reminder date. For sent reminders, only show sent date
            if (isPending)
              Text(
                "Date: ${DateFormat('MMM d, yyyy • h:mm a').format(reminder.reminderDate)}",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              )
            else if (reminder.sentAt != null)
              Text(
                "Sent: ${DateFormat('MMM d, yyyy • h:mm a').format(reminder.sentAt!)}",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
          ],
        ),
        trailing: isPending
            ? IconButton(
                icon: const Icon(Icons.send, color: Color(0xff1458a3)),
                tooltip: "Send Reminder",
                onPressed: () => _sendReminder(reminder),
              )
            : null,
        onTap: () => _showReminderDetails(reminder),
      ),
    );
  }

  String _getReminderTypeText(String type) {
    switch (type) {
      case 'after_due_date':
        return 'Payment Due Reminder';
      case 'overdue':
        return 'Overdue Payment';
      case 'manual':
        return 'Manual Reminder';
      default:
        return 'Payment Reminder';
    }
  }

  Future<void> _sendReminder(PaymentReminder reminder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Send Reminder"),
        content: Text(
          "Send payment reminder to ${reminder.studentName}?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff1458a3)),
            child: const Text("Send", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _paymentService.sendPaymentReminder(
        invoiceId: reminder.invoiceId,
        studentId: reminder.studentId,
      );

      // Note: The reminder is already marked as sent in sendPaymentReminder
      // This is just for UI feedback

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reminder sent successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showReminderDetails(PaymentReminder reminder) async {
    final invoice = await _paymentService.getInvoice(reminder.invoiceId);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reminder Details"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Student:", reminder.studentName),
              _detailRow("Email:", reminder.studentEmail),
              _detailRow("Type:", _getReminderTypeText(reminder.reminderType)),
              _detailRow("Date:", DateFormat('MMM d, yyyy • h:mm a').format(reminder.reminderDate)),
              _detailRow("Status:", reminder.sent ? "Sent" : "Pending"),
              if (reminder.sentAt != null)
                _detailRow("Sent At:", DateFormat('MMM d, yyyy • h:mm a').format(reminder.sentAt!)),
              if (invoice != null) ...[
                const Divider(),
                _detailRow("Invoice Month:", DateFormat('MMMM yyyy').format(invoice.month)),
                _detailRow("Amount:", "RM ${invoice.totalAmount.toStringAsFixed(2)}"),
                _detailRow("Status:", invoice.status.toUpperCase()),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
