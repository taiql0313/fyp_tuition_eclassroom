# Payment Module Setup Guide

## Overview
The Fees & Payment Module has been fully integrated with Firebase. It includes:
- Monthly billing based on enrolled subjects
- Automated payment reminders (before 2nd week of month)
- PayPal Sandbox integration (web-based)
- Admin payment management
- Payment reports and exports

## Firebase Collections Created

### 1. `invoices`
Stores monthly invoices for students
- Fields: studentId, studentName, month, totalAmount, items (subject breakdown), dueDate, status, etc.

### 2. `payment_transactions`
Stores all payment transactions
- Fields: invoiceId, studentId, amount, paymentMethod, status, paypalOrderId, etc.

### 3. `payment_reminders`
Stores payment reminder records
- Fields: invoiceId, studentId, reminderDate, reminderType, sent, etc.

## Setup Instructions

### 1. Update Firestore Rules
Copy the updated rules from `firestore_rules.txt` to your Firebase Console.

### 2. PayPal Sandbox Setup

#### Step 1: Create PayPal Sandbox Account
1. Go to https://developer.paypal.com/
2. Sign in or create an account
3. Navigate to Dashboard > Sandbox > Accounts
4. Create a test business account

#### Step 2: Get API Credentials
1. Go to Dashboard > My Apps & Credentials
2. Create a new app (Sandbox)
3. Copy the **Client ID** and **Secret**

#### Step 3: Update Payment Service
In `lib/services/payment_service.dart`, update these constants:
```dart
static const String paypalClientId = 'YOUR_PAYPAL_CLIENT_ID';
static const String paypalSecret = 'YOUR_PAYPAL_SECRET';
```

#### Step 4: Implement PayPal Order Creation
The current implementation uses a web-based approach. To fully integrate:

1. **Option A: Use PayPal REST API directly**
   - Make HTTP requests to PayPal Sandbox API
   - Create orders using `/v2/checkout/orders` endpoint
   - Handle webhook callbacks for payment confirmation

2. **Option B: Use a backend service**
   - Create a Cloud Function or backend API
   - Handle PayPal API calls server-side (more secure)
   - Return approval URLs to the app

### 3. Monthly Invoice Generation

Invoices are generated automatically when:
- Admin clicks "Generate Monthly Invoices" button in Payment Management
- Or you can set up a Cloud Function to run monthly

**To set up automated monthly generation:**
1. Create a Cloud Function that runs on the 1st of each month
2. Call `generateMonthlyInvoicesForAllStudents()`
3. This will create invoices for all students based on their enrolled subjects

### 4. Payment Reminders

Reminders are checked when:
- Student opens the Payment page
- Admin opens Payment Management page
- Or set up a scheduled Cloud Function

**Reminder Logic:**
- If payment is not made before the 2nd week (14th day) of the month, a reminder is created
- Reminders are stored in `payment_reminders` collection
- In production, you should send actual email/notification from here

**To implement email notifications:**
1. Set up Firebase Cloud Functions
2. Listen to `payment_reminders` collection
3. Send email when new reminder is created with `sent: false`
4. Update reminder with `sent: true` after sending

### 5. Testing

#### Test Monthly Invoice Generation:
1. Login as admin
2. Go to Payment Management
3. Click refresh icon (Generate Monthly Invoices)
4. Check that invoices are created for all students

#### Test Payment Flow:
1. Login as student
2. Go to Payment page
3. Click "Pay Now" on pending invoice
4. Should open PayPal Sandbox checkout (currently returns mock URL)

#### Test Manual Payment (Admin):
1. Login as admin
2. Go to Payment Management > Invoices tab
3. Click on a pending invoice
4. Click "Record Payment"
5. Enter notes and confirm
6. Invoice should be marked as paid

## Features Implemented

✅ Monthly billing calculation based on enrolled subjects
✅ Invoice generation with subject breakdown
✅ Payment status tracking (pending, paid, overdue)
✅ Payment reminders (before 2nd week of month)
✅ Student payment page with real-time data
✅ Payment history for students
✅ Admin payment management dashboard
✅ Manual payment recording (admin)
✅ Payment reports and PDF export
✅ Transaction history
✅ Outstanding balance calculation

## Features Pending Full Implementation

⚠️ **PayPal Sandbox Integration**
- Currently returns mock approval URL
- Need to implement actual PayPal API calls
- Need to handle payment callbacks/webhooks

⚠️ **Email Notifications**
- Reminder records are created but not sent
- Need to implement email service (Firebase Cloud Functions + SendGrid/SES)

⚠️ **Automated Monthly Invoice Generation**
- Currently manual (admin clicks button)
- Should be automated via Cloud Function

## Important Notes

1. **Subject Prices**: Fees are calculated from the `subjects` collection. Make sure all subjects have prices set.

2. **Due Dates**: Currently set to 14th of each month (2nd week). You can modify this in `PaymentService.generateMonthlyInvoice()`.

3. **PayPal Integration**: The current implementation is a placeholder. You'll need to:
   - Implement actual PayPal API calls
   - Handle OAuth token generation
   - Process payment callbacks
   - Update invoice status when payment completes

4. **Security**: PayPal credentials should be stored securely (use environment variables or Firebase Functions).

## Next Steps

1. Set up PayPal Sandbox account and get credentials
2. Implement actual PayPal API integration
3. Set up Cloud Functions for:
   - Monthly invoice generation
   - Payment reminder emails
   - PayPal webhook handling
4. Test the complete payment flow
5. Set up production PayPal account when ready
