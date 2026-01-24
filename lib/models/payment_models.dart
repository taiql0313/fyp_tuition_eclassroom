import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a monthly invoice for a student
class Invoice {
  final String id;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final DateTime month; // Year and month of the invoice
  final double totalAmount;
  final List<InvoiceItem> items; // Subject fees breakdown
  final DateTime dueDate; // Usually 2nd week of the month
  final String status; // 'pending', 'paid', 'overdue', 'cancelled'
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? paymentTransactionId; // Link to payment transaction

  Invoice({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.month,
    required this.totalAmount,
    required this.items,
    required this.dueDate,
    this.status = 'pending',
    required this.createdAt,
    this.paidAt,
    this.paymentTransactionId,
  });

  factory Invoice.fromMap(String id, Map<String, dynamic> map) {
    return Invoice(
      id: id,
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      studentEmail: map['studentEmail'] ?? '',
      month: (map['month'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      items: (map['items'] as List<dynamic>?)
              ?.map((item) => InvoiceItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      dueDate: (map['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: map['status'] ?? 'pending',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
      paymentTransactionId: map['paymentTransactionId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'month': Timestamp.fromDate(month),
      'totalAmount': totalAmount,
      'items': items.map((item) => item.toMap()).toList(),
      'dueDate': Timestamp.fromDate(dueDate),
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'paymentTransactionId': paymentTransactionId,
    };
  }

  bool get isOverdue {
    if (status == 'paid') return false;
    // Invoice is overdue only if we're in the next month or later
    // Example: January invoice is overdue starting from February 1st
    final invoiceMonth = DateTime(month.year, month.month, 1);
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    return currentMonth.isAfter(invoiceMonth);
  }

  bool get needsReminder {
    if (status == 'paid') return false;
    // Check if we're in the 2nd week of the month and payment is still pending
    final now = DateTime.now();
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final nowOnly = DateTime(now.year, now.month, now.day);
    
    // Remind if we're past the 1st week but before due date
    final firstWeekEnd = DateTime(dueDate.year, dueDate.month, 7);
    return nowOnly.isAfter(firstWeekEnd) && nowOnly.isBefore(dueDateOnly);
  }
}

/// Represents an item in an invoice (subject fee)
class InvoiceItem {
  final String subjectId;
  final String subjectName;
  final String classId;
  final String className;
  final double price;

  InvoiceItem({
    required this.subjectId,
    required this.subjectName,
    required this.classId,
    required this.className,
    required this.price,
  });

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      subjectId: map['subjectId'] ?? '',
      subjectName: map['subjectName'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjectId': subjectId,
      'subjectName': subjectName,
      'classId': classId,
      'className': className,
      'price': price,
    };
  }
}

/// Represents a payment transaction
class PaymentTransaction {
  final String id;
  final String invoiceId;
  final String studentId;
  final String studentName;
  final double amount;
  final String paymentMethod; // 'paypal', 'manual', 'other'
  final String status; // 'pending', 'completed', 'failed', 'cancelled'
  final String? paypalOrderId; // PayPal order ID if using PayPal
  final String? paypalTransactionId; // PayPal transaction ID
  final double? paypalAmount; // Amount charged on PayPal (USD)
  final String? paypalCurrency; // Currency charged on PayPal
  final double? exchangeRate; // MYR to USD rate used for conversion
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? notes; // Admin notes for manual payments

  PaymentTransaction({
    required this.id,
    required this.invoiceId,
    required this.studentId,
    required this.studentName,
    required this.amount,
    required this.paymentMethod,
    this.status = 'pending',
    this.paypalOrderId,
    this.paypalTransactionId,
    this.paypalAmount,
    this.paypalCurrency,
    this.exchangeRate,
    required this.createdAt,
    this.completedAt,
    this.notes,
  });

  factory PaymentTransaction.fromMap(String id, Map<String, dynamic> map) {
    return PaymentTransaction(
      id: id,
      invoiceId: map['invoiceId'] ?? '',
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['paymentMethod'] ?? 'paypal',
      status: map['status'] ?? 'pending',
      paypalOrderId: map['paypalOrderId'],
      paypalTransactionId: map['paypalTransactionId'],
      paypalAmount: (map['paypalAmount'] as num?)?.toDouble(),
      paypalCurrency: map['paypalCurrency'],
      exchangeRate: (map['exchangeRate'] as num?)?.toDouble(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (map['completedAt'] as Timestamp?)?.toDate(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceId': invoiceId,
      'studentId': studentId,
      'studentName': studentName,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'status': status,
      'paypalOrderId': paypalOrderId,
      'paypalTransactionId': paypalTransactionId,
      'paypalAmount': paypalAmount,
      'paypalCurrency': paypalCurrency,
      'exchangeRate': exchangeRate,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'notes': notes,
    };
  }
}

/// Represents a payment reminder notification
class PaymentReminder {
  final String id;
  final String invoiceId;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final DateTime reminderDate;
  final String reminderType; // 'first_week', 'due_date', 'overdue'
  final bool sent;
  final DateTime? sentAt;

  PaymentReminder({
    required this.id,
    required this.invoiceId,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.reminderDate,
    required this.reminderType,
    this.sent = false,
    this.sentAt,
  });

  factory PaymentReminder.fromMap(String id, Map<String, dynamic> map) {
    return PaymentReminder(
      id: id,
      invoiceId: map['invoiceId'] ?? '',
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      studentEmail: map['studentEmail'] ?? '',
      reminderDate: (map['reminderDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reminderType: map['reminderType'] ?? 'first_week',
      sent: map['sent'] ?? false,
      sentAt: (map['sentAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceId': invoiceId,
      'studentId': studentId,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'reminderDate': Timestamp.fromDate(reminderDate),
      'reminderType': reminderType,
      'sent': sent,
      'sentAt': sentAt != null ? Timestamp.fromDate(sentAt!) : null,
    };
  }
}
