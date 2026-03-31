import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class EmailService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── SMTP CONFIG ───
  static const String _smtpEmail = 'email@gmail.com';
  static const String _smtpPassword = 'password';
  static const String _senderName = 'Tuition E-Classroom';

  static SmtpServer get _smtpServer => gmail(_smtpEmail, _smtpPassword);

  static Future<void> sendPaymentReceipt({
    required String toEmail,
    required PaymentTransaction transaction,
    required Invoice invoice,
  }) async {
    if (_smtpEmail == 'email@gmail.com') {
      print('EmailService: SMTP not configured — skipping email send.');
      return;
    }

    try {
      final completedDate = DateFormat('dd MMM yyyy, h:mm a').format(
        TimezoneHelper.toMalaysiaTime(transaction.completedAt ?? transaction.createdAt),
      );
      final invoiceMonth = DateFormat('MMMM yyyy').format(
        TimezoneHelper.toMalaysiaTime(invoice.month),
      );

      final itemsHtml = invoice.items.map((item) => '''
        <tr>
          <td style="padding:12px 16px;border-bottom:1px solid #eee;font-size:14px;color:#333;">
            ${item.subjectName}<br>
            <span style="font-size:12px;color:#888;">${item.className}</span>
          </td>
          <td style="padding:12px 16px;border-bottom:1px solid #eee;font-size:14px;color:#333;text-align:right;">
            RM ${item.price.toStringAsFixed(2)}
          </td>
        </tr>''').join('\n');

      final paypalSection = (transaction.paypalAmount != null && transaction.paypalCurrency != null)
          ? '''
        <tr>
          <td style="padding:8px 16px;font-size:13px;color:#666;">PayPal Charge</td>
          <td style="padding:8px 16px;font-size:13px;color:#666;text-align:right;">
            ${transaction.paypalCurrency} ${transaction.paypalAmount!.toStringAsFixed(2)}
          </td>
        </tr>'''
          : '';

      final exchangeSection = (transaction.exchangeRate != null)
          ? '''
        <tr>
          <td style="padding:8px 16px;font-size:13px;color:#666;">Exchange Rate</td>
          <td style="padding:8px 16px;font-size:13px;color:#666;text-align:right;">
            1 MYR ≈ ${transaction.exchangeRate!.toStringAsFixed(4)} USD
          </td>
        </tr>'''
          : '';

      final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#f4f6f9;font-family:'Segoe UI',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f9;padding:32px 0;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">

        <!-- Header -->
        <tr>
          <td style="background:#1458a3;padding:32px 40px;">
            <h1 style="margin:0;color:#fff;font-size:24px;font-weight:700;">Payment Receipt</h1>
            <p style="margin:6px 0 0;color:rgba(255,255,255,0.85);font-size:14px;">Tuition E-Classroom</p>
          </td>
        </tr>

        <!-- Success Badge -->
        <tr>
          <td style="padding:28px 40px 0;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="background:#e8f5e9;border-radius:8px;padding:16px 20px;text-align:center;">
                  <span style="color:#2e7d32;font-size:16px;font-weight:600;">&#10004; Payment Successful</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Receipt Info -->
        <tr>
          <td style="padding:24px 40px 0;">
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="padding:6px 0;font-size:13px;color:#888;">Receipt No.</td>
                <td style="padding:6px 0;font-size:13px;color:#333;text-align:right;font-weight:600;">
                  ${transaction.id.substring(0, 12).toUpperCase()}
                </td>
              </tr>
              <tr>
                <td style="padding:6px 0;font-size:13px;color:#888;">Date</td>
                <td style="padding:6px 0;font-size:13px;color:#333;text-align:right;">$completedDate</td>
              </tr>
              <tr>
                <td style="padding:6px 0;font-size:13px;color:#888;">Student</td>
                <td style="padding:6px 0;font-size:13px;color:#333;text-align:right;font-weight:600;">
                  ${transaction.studentName}
                </td>
              </tr>
              <tr>
                <td style="padding:6px 0;font-size:13px;color:#888;">Invoice Month</td>
                <td style="padding:6px 0;font-size:13px;color:#333;text-align:right;">$invoiceMonth</td>
              </tr>
              <tr>
                <td style="padding:6px 0;font-size:13px;color:#888;">Payment Method</td>
                <td style="padding:6px 0;font-size:13px;color:#333;text-align:right;">
                  ${transaction.paymentMethod.toUpperCase()}
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Divider -->
        <tr><td style="padding:20px 40px 0;"><hr style="border:none;border-top:1px solid #eee;"></td></tr>

        <!-- Items Table -->
        <tr>
          <td style="padding:16px 40px 0;">
            <p style="margin:0 0 12px;font-size:15px;font-weight:600;color:#333;">Subject Breakdown</p>
            <table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
              <tr style="background:#f8fafc;">
                <td style="padding:10px 16px;font-size:12px;font-weight:700;color:#666;text-transform:uppercase;letter-spacing:0.5px;">
                  Subject / Class
                </td>
                <td style="padding:10px 16px;font-size:12px;font-weight:700;color:#666;text-transform:uppercase;letter-spacing:0.5px;text-align:right;">
                  Amount
                </td>
              </tr>
              $itemsHtml
            </table>
          </td>
        </tr>

        <!-- Total -->
        <tr>
          <td style="padding:16px 40px 0;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background:#f8fafc;border-radius:8px;">
              <tr>
                <td style="padding:16px 20px;font-size:16px;font-weight:700;color:#333;">Total Paid</td>
                <td style="padding:16px 20px;font-size:20px;font-weight:700;color:#1458a3;text-align:right;">
                  RM ${transaction.amount.toStringAsFixed(2)}
                </td>
              </tr>
              $paypalSection
              $exchangeSection
            </table>
          </td>
        </tr>

        ${transaction.paypalOrderId != null ? '''
        <tr>
          <td style="padding:12px 40px 0;">
            <p style="margin:0;font-size:12px;color:#999;">PayPal Order ID: ${transaction.paypalOrderId}</p>
          </td>
        </tr>''' : ''}

        <!-- Footer -->
        <tr>
          <td style="padding:32px 40px;">
            <p style="margin:0;font-size:14px;color:#666;text-align:center;">
              Thank you for your payment!
            </p>
            <p style="margin:8px 0 0;font-size:12px;color:#999;text-align:center;">
              This is an automated receipt from Tuition E-Classroom.<br>
              Please keep this email for your records.
            </p>
          </td>
        </tr>

        <!-- Bottom Bar -->
        <tr>
          <td style="background:#1458a3;padding:16px 40px;text-align:center;">
            <p style="margin:0;font-size:12px;color:rgba(255,255,255,0.7);">
              &copy; ${DateTime.now().year} Tuition E-Classroom. All rights reserved.
            </p>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>''';

      final message = Message()
        ..from = Address(_smtpEmail, _senderName)
        ..recipients.add(toEmail)
        ..subject = 'Payment Receipt - RM ${transaction.amount.toStringAsFixed(2)} ($invoiceMonth)'
        ..html = html;

      await send(message, _smtpServer);
      print('EmailService: Receipt sent to $toEmail');
    } catch (e) {
      print('EmailService: Failed to send receipt: $e');
    }
  }

  /// Called after payment is captured — fetches invoice + user email, then sends.
  static Future<void> sendReceiptForTransaction(PaymentTransaction transaction) async {
    try {
      final invoiceDoc = await _db.collection('invoices').doc(transaction.invoiceId).get();
      if (!invoiceDoc.exists) {
        print('EmailService: Invoice ${transaction.invoiceId} not found');
        return;
      }
      final invoice = Invoice.fromMap(invoiceDoc.id, invoiceDoc.data()!);

      final userDoc = await _db.collection('users').doc(transaction.studentId).get();
      final email = userDoc.data()?['email'] as String?;
      if (email == null || email.isEmpty) {
        print('EmailService: No email found for student ${transaction.studentId}');
        return;
      }

      await sendPaymentReceipt(
        toEmail: email,
        transaction: transaction,
        invoice: invoice,
      );
    } catch (e) {
      print('EmailService: Error in sendReceiptForTransaction: $e');
    }
  }
}
