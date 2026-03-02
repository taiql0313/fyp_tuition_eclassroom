import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/services/subject_service.dart';
import 'package:fyp_tuition_eclassroom/models/subject_model.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:fyp_tuition_eclassroom/services/notification_service.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final SubjectService _subjectService = SubjectService();

  final String _invoicesCol = 'invoices';
  final String _transactionsCol = 'payment_transactions';
  final String _remindersCol = 'payment_reminders';

  // PayPal Sandbox credentials
  static const String paypalClientId = 'AaTDyCy-DX6Q8TyXj8yK-rM6eGxd992oFKZQZ0_CDrhc6q-m-MriUg2rv8XDOt0NMeCgPhQU4HTNxkrj';
  static const String paypalSecret = 'ELmzhCaz7ddMoTc2j2swvfuTlfZ3K66D7y4eyePGUZCw__rO2zWXdkzHkozSZjawemnwkzCPnd_vr3cd';
  static const String paypalBaseUrl = 'https://api.sandbox.paypal.com'; // Sandbox URL
  static const double _myrToUsdRate = 0.21; // Update as needed (approx 1 MYR -> USD)

  double convertMyrToUsd(double amountMyr) {
    final converted = amountMyr * _myrToUsdRate;
    return double.parse(converted.toStringAsFixed(2));
  }

  Future<Map<String, String>> _getCurrentUserInfo() async {
    final user = _auth.currentUser;
    if (user == null) {
      return {
        'name': 'System',
        'role': 'system',
        'id': '',
      };
    }

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data();
      final name = data?['displayName'] as String? ?? user.displayName ?? user.email ?? 'User';
      final role = data?['role'] as String? ?? 'user';
      return {
        'name': name,
        'role': role,
        'id': user.uid,
      };
    } catch (_) {
      return {
        'name': user.displayName ?? user.email ?? 'User',
        'role': 'user',
        'id': user.uid,
      };
    }
  }

  Future<void> _logPaymentEvent({
    required String action,
    required String details,
    String type = 'Info',
    bool? success,
  }) async {
    final info = await _getCurrentUserInfo();
    if (info['id']!.isEmpty) return;
    try {
      await _db.collection('system_logs').add({
        'type': type,
        'category': 'Fees & Payment',
        'action': action,
        'user': info['name'],
        'role': info['role'],
        'userId': info['id'],
        'details': details,
        'success': success,
        'time': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging payment event: $e');
    }
  }

  /// Generate monthly invoice for a student based on their enrolled subjects
  Future<Invoice> generateMonthlyInvoice(String studentId, DateTime month) async {
    // Get student data
    final student = await _userService.getUser(studentId);
    if (student == null) throw Exception('Student not found');

    // Get all classes the student is enrolled in
    final classes = <Map<String, dynamic>>[];
    for (var classId in student.classIds) {
      final classDoc = await _db.collection('classrooms').doc(classId).get();
      if (classDoc.exists) {
        classes.add({'id': classId, ...classDoc.data()!});
      }
    }

    if (classes.isEmpty) {
      throw Exception('Student is not enrolled in any classes');
    }

    // Calculate fees based on subjects
    final invoiceItems = <InvoiceItem>[];
    double totalAmount = 0.0;

    for (var classData in classes) {
      final subjectId = classData['subjectId'] as String?;
      if (subjectId == null) continue;

      // Get subject to get the price
      final subject = await _subjectService.getSubject(subjectId);
      if (subject == null || !subject.isActive) continue;

      // Add to invoice items
      invoiceItems.add(InvoiceItem(
        subjectId: subjectId,
        subjectName: subject.name,
        classId: classData['id'],
        className: classData['className'] ?? 'Class',
        price: subject.price,
      ));

      totalAmount += subject.price;
    }

    if (invoiceItems.isEmpty) {
      throw Exception('No active subjects found for student');
    }

    // Calculate due date (2nd week of the month - 14th day)
    final baseDueDate = DateTime(month.year, month.month, 14);

    // Check if invoices already exist for this month
    final monthStart = DateTime(month.year, month.month, 1);
    final existingInvoicesSnapshot = await _db
        .collection(_invoicesCol)
        .where('studentId', isEqualTo: studentId)
        .where('month', isEqualTo: Timestamp.fromDate(monthStart))
        .get();

    if (existingInvoicesSnapshot.docs.isNotEmpty) {
      final existingInvoices = existingInvoicesSnapshot.docs
          .map((doc) => Invoice.fromMap(doc.id, doc.data()))
          .toList();

      final billedClassIds = <String>{};
      for (var inv in existingInvoices) {
        for (var item in inv.items) {
          billedClassIds.add(item.classId);
        }
      }

      final missingItems =
          invoiceItems.where((item) => !billedClassIds.contains(item.classId)).toList();

      if (missingItems.isEmpty) {
        final monthName = DateFormat('MMMM yyyy').format(monthStart);
        await _logPaymentEvent(
          action: 'Invoice Up To Date',
          details: 'No new classes to bill for $studentId ($monthName).',
          type: 'Info',
          success: true,
        );
        return existingInvoices.first;
      }

      final additionalAmount =
          missingItems.fold<double>(0.0, (sum, item) => sum + item.price);

      // If already past due date in the same month, give 7 days for the new charges
      final now = DateTime.now();
      final adjustedDueDate = (now.year == month.year &&
              now.month == month.month &&
              now.isAfter(baseDueDate))
          ? DateTime(now.year, now.month, now.day).add(const Duration(days: 7))
          : baseDueDate;

      final supplementalInvoice = Invoice(
        id: '',
        studentId: studentId,
        studentName: student.displayName,
        studentEmail: student.email,
        month: DateTime(month.year, month.month, 1),
        totalAmount: additionalAmount,
        items: missingItems,
        dueDate: adjustedDueDate,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      final docRef =
          await _db.collection(_invoicesCol).add(supplementalInvoice.toMap());
      await _logPaymentEvent(
        action: 'Supplementary Invoice Created',
        details: 'Supplementary invoice ${docRef.id} created for ${student.displayName} '
            '($studentId) with ${missingItems.length} new class(es), '
            'RM ${additionalAmount.toStringAsFixed(2)}.',
        success: true,
      );
      try {
        await NotificationService().createForUser(
          userId: studentId,
          type: 'payment',
          title: 'New Invoice',
          message: 'Supplementary invoice for ${DateFormat('MMM yyyy').format(month)}: RM ${additionalAmount.toStringAsFixed(2)}.',
        );
      } catch (e) {
        print('Could not create invoice notification: $e');
      }
      return Invoice.fromMap(docRef.id, supplementalInvoice.toMap());
    }

    // Create new invoice
    final invoice = Invoice(
      id: '',
      studentId: studentId,
      studentName: student.displayName,
      studentEmail: student.email,
      month: DateTime(month.year, month.month, 1),
      totalAmount: totalAmount,
      items: invoiceItems,
      dueDate: baseDueDate,
      status: 'pending',
      createdAt: DateTime.now(),
    );

    final docRef = await _db.collection(_invoicesCol).add(invoice.toMap());
    await _logPaymentEvent(
      action: 'Invoice Created',
      details: 'Invoice ${docRef.id} created for ${student.displayName} ($studentId), '
          '${DateFormat('MMM yyyy').format(invoice.month)}, RM ${totalAmount.toStringAsFixed(2)}.',
      success: true,
    );
    // Notify student that a new invoice is available
    try {
      await NotificationService().createForUser(
        userId: studentId,
        type: 'payment',
        title: 'New Invoice',
        message: 'Invoice for ${DateFormat('MMM yyyy').format(invoice.month)}: RM ${totalAmount.toStringAsFixed(2)}. Please pay by ${DateFormat('d MMM').format(invoice.dueDate)}.',
      );
    } catch (e) {
      print('Could not create invoice notification: $e');
    }
    return Invoice.fromMap(docRef.id, invoice.toMap());
  }

  /// Check if invoices have been generated for the current month
  Future<bool> hasInvoicesForMonth(DateTime month) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final snapshot = await _db
        .collection(_invoicesCol)
        .where('month', isEqualTo: Timestamp.fromDate(monthStart))
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Generate invoices for all students for the current month
  Future<void> generateMonthlyInvoicesForAllStudents() async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);

    // Get all students
    final students = await _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();

    for (var studentDoc in students.docs) {
      try {
        await generateMonthlyInvoice(studentDoc.id, currentMonth);
      } catch (e) {
        print('Error generating invoice for ${studentDoc.id}: $e');
        // Continue with other students
      }
    }
  }

  /// Automatically generate invoices for current month if not already generated
  /// This should be called when admin logs in or app starts
  Future<void> autoGenerateMonthlyInvoicesIfNeeded() async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);

    // Check if invoices already exist for this month
    final hasInvoices = await hasInvoicesForMonth(currentMonth);
    
    if (!hasInvoices) {
      print('Auto-generating monthly invoices for ${DateFormat('MMMM yyyy').format(currentMonth)}');
      try {
        await generateMonthlyInvoicesForAllStudents();
        print('Monthly invoices auto-generated successfully');
      } catch (e) {
        print('Error auto-generating monthly invoices: $e');
        // Don't throw - this is a background operation
      }
    } else {
      print('Invoices already exist for ${DateFormat('MMMM yyyy').format(currentMonth)}');
    }
  }

  /// Get invoices for a student
  Stream<List<Invoice>> streamStudentInvoices(String studentId) {
    return _db
        .collection(_invoicesCol)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final invoices = snapshot.docs
              .map((doc) => Invoice.fromMap(doc.id, doc.data()))
              .toList();
          // Sort in memory to avoid index issues
          invoices.sort((a, b) => b.month.compareTo(a.month));
          return invoices;
        })
        .handleError((error) {
          print('Error streaming student invoices: $error');
          return <Invoice>[];
        });
  }

  /// Get pending invoices for a student
  /// Get unpaid invoices for a student (pending and overdue)
  Future<List<Invoice>> getPendingInvoices(String studentId) async {
    final snapshot = await _db
        .collection(_invoicesCol)
        .where('studentId', isEqualTo: studentId)
        .where('status', whereIn: ['pending', 'overdue'])
        .get();

    final invoices = snapshot.docs
        .map((doc) => Invoice.fromMap(doc.id, doc.data()))
        .toList();
    
    // Sort by due date (earliest first)
    invoices.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return invoices;
  }

  /// Get outstanding balance for a student (includes pending and overdue invoices)
  Future<double> getOutstandingBalance(String studentId) async {
    // Get all unpaid invoices (pending and overdue)
    final snapshot = await _db
        .collection(_invoicesCol)
        .where('studentId', isEqualTo: studentId)
        .where('status', whereIn: ['pending', 'overdue'])
        .get();

    double total = 0.0;
    for (var doc in snapshot.docs) {
      final invoice = Invoice.fromMap(doc.id, doc.data());
      total += invoice.totalAmount;
    }
    return total;
  }

  /// Get PayPal access token
  Future<String> _getPayPalAccessToken() async {
    final credentials = base64Encode(utf8.encode('$paypalClientId:$paypalSecret'));
    
    final response = await http.post(
      Uri.parse('$paypalBaseUrl/v1/oauth2/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Basic $credentials',
      },
      body: 'grant_type=client_credentials',
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('PayPal access token request timed out. Please check your internet connection.');
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['access_token'] as String;
    } else {
      throw Exception('Failed to get PayPal access token: ${response.body}');
    }
  }

  /// Create PayPal order (Sandbox)
  Future<Map<String, dynamic>> createPayPalOrder({
    required String invoiceId,
    required double amount,
    required String studentId,
    required String studentName,
  }) async {
    try {
      // Check if there's already a pending transaction for this invoice
      // Must include studentId in query to satisfy Firestore security rules
      // Query by studentId and invoiceId, then filter status in code
      final existingTransactions = await _db
          .collection(_transactionsCol)
          .where('studentId', isEqualTo: studentId)
          .where('invoiceId', isEqualTo: invoiceId)
          .get();
      
      // Filter by status in code (pending or completed)
      final filteredTransactions = existingTransactions.docs
          .where((doc) {
            final data = doc.data();
            final status = data['status'] as String?;
            return status == 'pending' || status == 'completed';
          })
          .toList();

      if (filteredTransactions.isNotEmpty) {
        final existing = PaymentTransaction.fromMap(
          filteredTransactions.first.id,
          filteredTransactions.first.data(),
        );
        
        // If already completed, return the existing transaction
        if (existing.status == 'completed') {
          throw Exception('Payment already completed for this invoice');
        }
        
        // If pending and has PayPal order ID, return existing order details
        if (existing.paypalOrderId != null) {
          // Get the approval URL from PayPal
          try {
            final orderStatus = await checkPayPalOrderStatus(existing.paypalOrderId!);
            final links = orderStatus['links'] as List<dynamic>?;
            String? approvalUrl;
            if (links != null) {
              for (var link in links) {
                if (link['rel'] == 'approve') {
                  approvalUrl = link['href'] as String;
                  break;
                }
              }
            }
            
            if (approvalUrl != null) {
              return {
                'transactionId': existingTransactions.docs.first.id,
                'orderId': existing.paypalOrderId!,
                'approvalUrl': approvalUrl,
              };
            }
          } catch (e) {
            // If we can't get the URL, continue to create a new order
            print('Error getting existing order URL: $e');
          }
        }
      }

      // Get access token
      final accessToken = await _getPayPalAccessToken();

      final usdAmount = convertMyrToUsd(amount);

      // Create transaction record first (store MYR amount and USD conversion)
      final transaction = PaymentTransaction(
        id: '',
        invoiceId: invoiceId,
        studentId: studentId,
        studentName: studentName,
        amount: amount,
        paymentMethod: 'paypal',
        status: 'pending',
        paypalAmount: usdAmount,
        paypalCurrency: 'USD',
        exchangeRate: _myrToUsdRate,
        createdAt: DateTime.now(),
      );

      final docRef = await _db.collection(_transactionsCol).add(transaction.toMap());

      // Create PayPal order (PayPal Sandbox does not support MYR)
      // Return / cancel URLs use a fake domain that we intercept in WebView.
      // They do NOT need to be real pages; we only use them as markers.
      final orderData = {
        'intent': 'CAPTURE',
        'purchase_units': [
          {
            'reference_id': invoiceId,
            'description': 'Tuition E-Classroom Payment - Invoice $invoiceId (RM ${amount.toStringAsFixed(2)})',
            'amount': {
              'currency_code': 'USD',
              'value': usdAmount.toStringAsFixed(2),
            },
          }
        ],
        'application_context': {
          'brand_name': 'Tuition E-Classroom',
          'landing_page': 'NO_PREFERENCE',
          'user_action': 'PAY_NOW',
          'return_url': 'https://tuition-eclassroom.com/paypal-success',
          'cancel_url': 'https://tuition-eclassroom.com/paypal-cancel',
        },
      };

      final response = await http.post(
        Uri.parse('$paypalBaseUrl/v2/checkout/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: json.encode(orderData),
      );

      if (response.statusCode == 201) {
        final orderResponse = json.decode(response.body);
        final orderId = orderResponse['id'] as String;
        
        // Find approval URL from links
        final links = orderResponse['links'] as List<dynamic>;
        String? approvalUrl;
        for (var link in links) {
          if (link['rel'] == 'approve') {
            approvalUrl = link['href'] as String;
            break;
          }
        }

        if (approvalUrl == null) {
          throw Exception('Approval URL not found in PayPal response');
        }

        // Update transaction with PayPal order ID
        await _db.collection(_transactionsCol).doc(docRef.id).update({
          'paypalOrderId': orderId,
        });

        await _logPaymentEvent(
          action: 'PayPal Order Created',
          details: 'Order $orderId created for invoice $invoiceId. '
              'RM ${amount.toStringAsFixed(2)} → USD ${usdAmount.toStringAsFixed(2)}.',
          success: true,
        );

        return {
          'transactionId': docRef.id,
          'orderId': orderId,
          'approvalUrl': approvalUrl,
        };
      } else {
        await _logPaymentEvent(
          action: 'PayPal Order Failed',
          details: 'Failed to create PayPal order for invoice $invoiceId. ${response.body}',
          type: 'Error',
          success: false,
        );
        throw Exception('Failed to create PayPal order: ${response.body}');
      }
    } catch (e) {
      // If PayPal API fails, still create transaction record for tracking
      print('PayPal API error: $e');
      rethrow;
    }
  }

  /// Check PayPal order status
  Future<Map<String, dynamic>> checkPayPalOrderStatus(String orderId) async {
    try {
      final accessToken = await _getPayPalAccessToken();
      
      final response = await http.get(
        Uri.parse('$paypalBaseUrl/v2/checkout/orders/$orderId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('PayPal API request timed out. Please check your internet connection.');
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to check order status: ${response.body}');
      }
    } catch (e) {
      print('Error checking PayPal order status: $e');
      rethrow;
    }
  }

  /// Capture PayPal payment (after user approves)
  Future<void> capturePayPalPayment(String orderId) async {
    try {
      print('Starting PayPal capture for order: $orderId');
      
      // Get current user to ensure we can query their transactions
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }
      final studentId = user.uid;
      
      // First, check the current order status
      final orderStatus = await checkPayPalOrderStatus(orderId);
      final currentStatus = orderStatus['status'] as String?;
      print('Current PayPal order status: $currentStatus');
      
      // Handle different statuses
      if (currentStatus == 'COMPLETED') {
        // Already completed, just update our records
        print('Order already completed, updating local records');
        await _updateTransactionFromCompletedOrder(orderId, orderStatus, studentId);
        return;
      } else if (currentStatus == 'APPROVED') {
        // Order is approved, proceed to capture
        print('Order is approved, proceeding to capture');
      } else if (currentStatus == 'CREATED' || currentStatus == 'SAVED') {
        throw Exception('Payment not completed on PayPal. Please complete the payment first, then click "Verify Payment".');
      } else if (currentStatus == 'VOIDED' || currentStatus == 'CANCELLED') {
        throw Exception('Payment was cancelled on PayPal. Please create a new payment.');
      } else {
        throw Exception('Payment status is "$currentStatus". Please complete the payment on PayPal first.');
      }

      // Get access token for capture
      print('Getting access token for capture');
      final accessToken = await _getPayPalAccessToken();

      // Capture the order
      print('Calling PayPal capture API');
      final response = await http.post(
        Uri.parse('$paypalBaseUrl/v2/checkout/orders/$orderId/capture'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('PayPal capture request timed out. Please try again.');
        },
      );

      print('PayPal capture response status: ${response.statusCode}');
      print('PayPal capture response body: ${response.body}');

      if (response.statusCode == 201) {
        final captureResponse = json.decode(response.body) as Map<String, dynamic>;
        final status = captureResponse['status'] as String?;
        print('Capture response status: $status');
        
        if (status == 'COMPLETED') {
          // Find transaction by PayPal order ID AND studentId (required for security rules)
          final transactionQuery = await _db
              .collection(_transactionsCol)
              .where('paypalOrderId', isEqualTo: orderId)
              .where('studentId', isEqualTo: studentId)
              .limit(1)
              .get();

          if (transactionQuery.docs.isEmpty) {
            throw Exception('Transaction not found in database');
          }

          final transactionDoc = transactionQuery.docs.first;
          final transactionId = transactionDoc.id;
          final transaction = PaymentTransaction.fromMap(transactionId, transactionDoc.data());
          final invoiceId = transaction.invoiceId;

          // Get payment transaction ID from PayPal response
          final purchaseUnits = captureResponse['purchase_units'] as List<dynamic>?;
          String? paypalTransactionId;
          if (purchaseUnits != null && purchaseUnits.isNotEmpty) {
            final payments = purchaseUnits[0]['payments'] as Map<String, dynamic>?;
            final captures = payments?['captures'] as List<dynamic>?;
            if (captures != null && captures.isNotEmpty) {
              paypalTransactionId = captures[0]['id'] as String;
            }
          }

          print('Updating transaction $transactionId to completed');
          // Update transaction (include studentId to satisfy security rules)
          await _db.collection(_transactionsCol).doc(transactionId).update({
            'status': 'completed',
            'paypalTransactionId': paypalTransactionId,
            'completedAt': FieldValue.serverTimestamp(),
            'studentId': transaction.studentId, // Ensure studentId is present for security rules
          });

          print('Updating invoice $invoiceId to paid');
          // Update invoice (also ensure studentId is present for security rules)
          await _db.collection(_invoicesCol).doc(invoiceId).update({
            'status': 'paid',
            'paidAt': FieldValue.serverTimestamp(),
            'paymentTransactionId': transactionId,
            'studentId': transaction.studentId, // Ensure studentId is present for security rules
          });
          
          await _logPaymentEvent(
            action: 'Payment Captured',
            details: 'PayPal payment captured. Invoice $invoiceId marked paid. '
                'Transaction $transactionId, PayPal ID: ${paypalTransactionId ?? 'n/a'}.',
            success: true,
          );

          print('Payment capture completed successfully');
        } else {
          throw Exception('PayPal capture returned status: $status (expected COMPLETED)');
        }
      } else {
        final errorBody = response.body;
        print('PayPal capture failed: $errorBody');
        throw Exception('PayPal capture failed: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('Error capturing PayPal payment: $e');
      rethrow;
    }
  }

  /// Helper method to update transaction from a completed PayPal order
  Future<void> _updateTransactionFromCompletedOrder(String orderId, Map<String, dynamic> orderData, String studentId) async {
    // Find transaction by PayPal order ID AND studentId (required for security rules)
    final transactionQuery = await _db
        .collection(_transactionsCol)
        .where('paypalOrderId', isEqualTo: orderId)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (transactionQuery.docs.isNotEmpty) {
      final transactionDoc = transactionQuery.docs.first;
      final transactionId = transactionDoc.id;
      final transaction = PaymentTransaction.fromMap(transactionId, transactionDoc.data());
      final invoiceId = transaction.invoiceId;

      // Get payment transaction ID from PayPal response
      final purchaseUnits = orderData['purchase_units'] as List<dynamic>?;
      String? paypalTransactionId;
      if (purchaseUnits != null && purchaseUnits.isNotEmpty) {
        final payments = purchaseUnits[0]['payments'] as Map<String, dynamic>?;
        final captures = payments?['captures'] as List<dynamic>?;
        if (captures != null && captures.isNotEmpty) {
          paypalTransactionId = captures[0]['id'] as String;
        }
      }

      // Update transaction (include studentId to satisfy security rules)
      await _db.collection(_transactionsCol).doc(transactionId).update({
        'status': 'completed',
        'paypalTransactionId': paypalTransactionId,
        'completedAt': FieldValue.serverTimestamp(),
        'studentId': transaction.studentId, // Ensure studentId is present for security rules
      });

      // Update invoice (include studentId to satisfy security rules)
      await _db.collection(_invoicesCol).doc(invoiceId).update({
        'status': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'paymentTransactionId': transactionId,
        'studentId': transaction.studentId, // Ensure studentId is present for security rules
      });
    }
  }

  /// Get a completed transaction by PayPal order ID and student ID
  Future<PaymentTransaction?> getTransactionByOrderId(String orderId, String studentId) async {
    final query = await _db
        .collection(_transactionsCol)
        .where('paypalOrderId', isEqualTo: orderId)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return PaymentTransaction.fromMap(query.docs.first.id, query.docs.first.data());
  }

  /// Complete PayPal payment (verify and update invoice) - Legacy method
  Future<void> completePayPalPayment({
    required String transactionId,
    required String paypalOrderId,
    required String paypalTransactionId,
  }) async {
    final transactionDoc = await _db.collection(_transactionsCol).doc(transactionId).get();
    if (!transactionDoc.exists) throw Exception('Transaction not found');

    final transaction = PaymentTransaction.fromMap(transactionId, transactionDoc.data()!);
    final invoiceId = transaction.invoiceId;

    // Update transaction
    await _db.collection(_transactionsCol).doc(transactionId).update({
      'status': 'completed',
      'paypalOrderId': paypalOrderId,
      'paypalTransactionId': paypalTransactionId,
      'completedAt': FieldValue.serverTimestamp(),
    });

    // Update invoice
    await _db.collection(_invoicesCol).doc(invoiceId).update({
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'paymentTransactionId': transactionId,
    });
  }

  /// Record manual payment (admin)
  Future<void> recordManualPayment({
    required String invoiceId,
    required String studentId,
    required String studentName,
    required double amount,
    String? notes,
  }) async {
    final transaction = PaymentTransaction(
      id: '',
      invoiceId: invoiceId,
      studentId: studentId,
      studentName: studentName,
      amount: amount,
      paymentMethod: 'manual',
      status: 'completed',
      createdAt: DateTime.now(),
      completedAt: DateTime.now(),
      notes: notes,
    );

    final docRef = await _db.collection(_transactionsCol).add(transaction.toMap());

    // Update invoice (include studentId for security rules)
    await _db.collection(_invoicesCol).doc(invoiceId).update({
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
      'paymentTransactionId': docRef.id,
      'studentId': studentId, // Ensure studentId is present for security rules
    });

    await _logPaymentEvent(
      action: 'Manual Payment Recorded',
      details: 'Invoice $invoiceId marked paid for $studentName ($studentId). '
          'RM ${amount.toStringAsFixed(2)}.',
      success: true,
    );
  }

  /// Get payment transactions for a student
  Stream<List<PaymentTransaction>> streamStudentTransactions(String studentId) {
    return _db
        .collection(_transactionsCol)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final transactions = snapshot.docs
              .map((doc) => PaymentTransaction.fromMap(doc.id, doc.data()))
              .toList();
          // Sort in memory to avoid index issues
          transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return transactions;
        })
        .handleError((error) {
          print('Error streaming student transactions: $error');
          return <PaymentTransaction>[];
        });
  }

  /// Get all transactions (admin)
  Stream<List<PaymentTransaction>> streamAllTransactions() {
    return _db
        .collection(_transactionsCol)
        .snapshots()
        .map((snapshot) {
          final transactions = snapshot.docs
              .map((doc) => PaymentTransaction.fromMap(doc.id, doc.data()))
              .toList();
          // Sort in memory to avoid index issues
          transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return transactions;
        })
        .handleError((error) {
          print('Error streaming transactions: $error');
          return <PaymentTransaction>[];
        });
  }

  /// Get all invoices (admin)
  Stream<List<Invoice>> streamAllInvoices() {
    return _db
        .collection(_invoicesCol)
        .snapshots()
        .map((snapshot) {
          final invoices = snapshot.docs
              .map((doc) => Invoice.fromMap(doc.id, doc.data()))
              .toList();
          // Sort in memory to avoid index issues
          invoices.sort((a, b) => b.month.compareTo(a.month));
          return invoices;
        })
        .handleError((error) {
          print('Error streaming invoices: $error');
          return <Invoice>[];
        });
  }

  /// Check and send payment reminders (should be called periodically)
  /// Checks for invoices that need reminders after 14th day (due date)
  Future<void> checkAndSendReminders() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Get all pending and overdue invoices
    final pendingInvoices = await _db
        .collection(_invoicesCol)
        .where('status', whereIn: ['pending', 'overdue'])
        .get();

    for (var invoiceDoc in pendingInvoices.docs) {
      final invoice = Invoice.fromMap(invoiceDoc.id, invoiceDoc.data());
      
      // Skip if already paid
      if (invoice.status == 'paid') continue;
      
      final dueDateOnly = DateTime(invoice.dueDate.year, invoice.dueDate.month, invoice.dueDate.day);
      
      // Check if we're past the 14th day (due date) and invoice is still pending
      if (today.isAfter(dueDateOnly) || today.isAtSameMomentAs(dueDateOnly)) {
        // Check if reminder already sent for this month
        final monthStart = DateTime(invoice.month.year, invoice.month.month, 1);
        final existingReminder = await _db
            .collection(_remindersCol)
            .where('invoiceId', isEqualTo: invoice.id)
            .where('reminderType', isEqualTo: 'after_due_date')
            .limit(1)
            .get();

        if (existingReminder.docs.isEmpty) {
          // Create reminder record
          final reminder = PaymentReminder(
            id: '',
            invoiceId: invoice.id,
            studentId: invoice.studentId,
            studentName: invoice.studentName,
            studentEmail: invoice.studentEmail,
            reminderDate: now,
            reminderType: 'after_due_date',
            sent: false,
          );

          await _db.collection(_remindersCol).add(reminder.toMap());
          
          // Create notification for student
          await _createPaymentNotification(
            studentId: invoice.studentId,
            invoiceId: invoice.id,
            month: invoice.month,
            amount: invoice.totalAmount,
            reminderType: 'after_due_date',
          );
          await _logPaymentEvent(
            action: 'Reminder Created',
            details: 'After-due reminder created for invoice ${invoice.id}.',
            success: true,
          );
          
          print('Reminder created for invoice ${invoice.id} (after due date)');
        }
      }

      // Check if overdue: Invoice is overdue only if we're in the next month or later
      // Example: January invoice (due date 14th Jan) is overdue starting from February 1st
      final invoiceMonth = DateTime(invoice.month.year, invoice.month.month, 1);
      final nextMonth = DateTime(invoice.month.year, invoice.month.month + 1, 1);
      final currentMonth = DateTime(now.year, now.month, 1);
      
      // Invoice is overdue if current month is after the invoice month
      // Example: January invoice (month = Jan 1) is overdue when current month is February 1 or later
      final isOverdue = currentMonth.isAfter(invoiceMonth);
      
      if (isOverdue && invoice.status != 'overdue' && invoice.status != 'paid') {
        // Update invoice status to overdue
        await _db.collection(_invoicesCol).doc(invoice.id).update({
          'status': 'overdue',
        });
        await _logPaymentEvent(
          action: 'Invoice Marked Overdue',
          details: 'Invoice ${invoice.id} status changed to overdue.',
          success: true,
        );
      }

      // Check if overdue reminder needed (only if we're in the next month or later)
      if (isOverdue) {
        final overdueReminder = await _db
            .collection(_remindersCol)
            .where('invoiceId', isEqualTo: invoice.id)
            .where('reminderType', isEqualTo: 'overdue')
            .limit(1)
            .get();

        if (overdueReminder.docs.isEmpty) {
          // Create overdue reminder
          final reminder = PaymentReminder(
            id: '',
            invoiceId: invoice.id,
            studentId: invoice.studentId,
            studentName: invoice.studentName,
            studentEmail: invoice.studentEmail,
            reminderDate: now,
            reminderType: 'overdue',
            sent: false,
          );

          await _db.collection(_remindersCol).add(reminder.toMap());
          
          // Create notification for student
          await _createPaymentNotification(
            studentId: invoice.studentId,
            invoiceId: invoice.id,
            month: invoice.month,
            amount: invoice.totalAmount,
            reminderType: 'overdue',
          );
          await _logPaymentEvent(
            action: 'Reminder Created',
            details: 'Overdue reminder created for invoice ${invoice.id}.',
            success: true,
          );
        }
      }
    }
  }

  /// Create a simple payment notification in Firestore
  Future<void> _createPaymentNotification({
    required String studentId,
    required String invoiceId,
    required DateTime month,
    required double amount,
    required String reminderType,
  }) async {
    final monthName = DateFormat('MMM yyyy').format(month);
    
    // Simple notification message
    final message = 'Payment reminder: RM ${amount.toStringAsFixed(2)} for $monthName is ${reminderType == 'overdue' ? 'overdue' : 'due'}.';

    try {
      await _db.collection('notifications').add({
        'userId': studentId,
        'type': 'payment',
        'title': 'Payment Reminder',
        'message': message,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error creating notification: $e');
      // Don't throw - notification is optional
    }
  }

  /// Manually send payment reminder to a specific student
  Future<void> sendPaymentReminder({
    required String invoiceId,
    required String studentId,
  }) async {
    final invoice = await getInvoice(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');
    if (invoice.status == 'paid') throw Exception('Invoice is already paid');

    final now = DateTime.now();
    
    // Check if reminder already sent today (simplified query to avoid composite index)
    // Get all reminders for this invoice and filter by date in code
    final allReminders = await _db
        .collection(_remindersCol)
        .where('invoiceId', isEqualTo: invoiceId)
        .where('reminderType', isEqualTo: 'manual')
        .get();

    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    
    // Filter in memory to check if reminder was sent today
    final todayReminders = allReminders.docs.where((doc) {
      final reminderData = doc.data();
      final reminderDate = (reminderData['reminderDate'] as Timestamp?)?.toDate();
      if (reminderDate == null) return false;
      return reminderDate.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
             reminderDate.isBefore(todayEnd);
    }).toList();

    if (todayReminders.isNotEmpty) {
      throw Exception('Reminder already sent today for this invoice');
    }

    // Create reminder record
    final reminder = PaymentReminder(
      id: '',
      invoiceId: invoice.id,
      studentId: invoice.studentId,
      studentName: invoice.studentName,
      studentEmail: invoice.studentEmail,
      reminderDate: now,
      reminderType: 'manual',
      sent: true,
      sentAt: now,
    );

    // Create reminder record
    final reminderRef = await _db.collection(_remindersCol).add(reminder.toMap());
    
    // Update reminder with sent status (already set in reminder object, but ensure it's saved)
    await reminderRef.update({
      'sent': true,
      'sentAt': Timestamp.fromDate(now),
    });
    
    // Create simple notification
    await _createPaymentNotification(
      studentId: invoice.studentId,
      invoiceId: invoice.id,
      month: invoice.month,
      amount: invoice.totalAmount,
      reminderType: 'manual',
    );

    await _logPaymentEvent(
      action: 'Manual Reminder Sent',
      details: 'Manual reminder sent for invoice ${invoice.id}.',
      success: true,
    );
  }

  /// Get all payment reminders (admin only - reads all reminders)
  Stream<List<PaymentReminder>> streamPaymentReminders() {
    // For admin, we can read all reminders
    // The security rules will filter based on admin status
    return _db
        .collection(_remindersCol)
        .snapshots()
        .map((snapshot) {
          final reminders = <PaymentReminder>[];
          for (var doc in snapshot.docs) {
            try {
              final reminder = PaymentReminder.fromMap(doc.id, doc.data());
              reminders.add(reminder);
            } catch (e) {
              print('Error parsing reminder ${doc.id}: $e');
              // Skip invalid reminders
            }
          }
          reminders.sort((a, b) => b.reminderDate.compareTo(a.reminderDate));
          return reminders;
        })
        .handleError((error) {
          print('Error streaming reminders: $error');
          return <PaymentReminder>[];
        });
  }

  /// Get reminders for a specific invoice
  Future<List<PaymentReminder>> getRemindersForInvoice(String invoiceId) async {
    final snapshot = await _db
        .collection(_remindersCol)
        .where('invoiceId', isEqualTo: invoiceId)
        .get();
    
    return snapshot.docs
        .map((doc) => PaymentReminder.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// Get invoice by ID
  Future<Invoice?> getInvoice(String invoiceId) async {
    final doc = await _db.collection(_invoicesCol).doc(invoiceId).get();
    if (!doc.exists) return null;
    return Invoice.fromMap(doc.id, doc.data()!);
  }

  /// Get transaction by ID
  Future<PaymentTransaction?> getTransaction(String transactionId) async {
    final doc = await _db.collection(_transactionsCol).doc(transactionId).get();
    if (!doc.exists) return null;
    return PaymentTransaction.fromMap(doc.id, doc.data()!);
  }
}
