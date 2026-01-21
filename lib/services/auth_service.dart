// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:fyp_tuition_eclassroom/models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fire = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  AuthService() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await cred.user?.updateDisplayName(displayName);
    await cred.user?.reload();

    final uid = cred.user!.uid;
    await _fire.collection('users').doc(uid).set({
      'email': email,
      'displayName': displayName,
      'role': 'student',
      'classIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> sendPasswordReset({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<AppUser?> fetchUserDoc(String uid) async {
    final doc = await _fire.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(uid, doc.data()!);
  }

  /// Admin creates user — CLIENT-SIDE APPROACH
  /// This will temporarily sign out the admin and then sign them back in automatically
  /// You need to pass the admin's password for re-authentication
  ///
  /// Returns null on success, or error message on failure.
  // lib/services/auth_service.dart

  /// Admin creates user — CLIENT-SIDE APPROACH (Improved)
  Future<String?> adminCreateUser({
    required String email,
    required String password,
    required String displayName,
    required String role,
    String? adminPassword,
  }) async {
    try {
      // 1. Get Current Admin
      final currentAdmin = currentUser;
      if (currentAdmin == null) return 'Not logged in';

      // 2. Check Admin Role (via Firestore check or Claims)
      final curDoc = await _fire.collection('users').doc(currentAdmin.uid).get();
      final curRole = curDoc.data()?['role'] as String?;
      if (curRole != 'admin') return 'Permission denied. Only admins can create users.';

      final adminEmail = currentAdmin.email;
      if (adminEmail == null) return 'Admin email not found';

      // --- NEW STEP: PRE-VALIDATE ADMIN PASSWORD ---
      // This ensures the password is correct BEFORE we log the admin out.
      if (adminPassword != null) {
        try {
          AuthCredential credential = EmailAuthProvider.credential(
              email: adminEmail,
              password: adminPassword
          );
          // If this fails, the code jumps to the catch block below
          await currentAdmin.reauthenticateWithCredential(credential);
        } catch (e) {
          return 'Incorrect Admin Password. Please try again.';
        }
      } else {
        return 'Admin password is required to perform this action.';
      }

      // 3. Create New User (This logs the admin out!)
      final newUserCred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUid = newUserCred.user!.uid;

      // 4. Update display name for new user
      await newUserCred.user?.updateDisplayName(displayName);

      // 5. Create Firestore document for new user
      await _fire.collection('users').doc(newUid).set({
        'email': email,
        'displayName': displayName,
        'role': role,
        'classIds': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 6. Sign out the NEW user
      await _auth.signOut();

      // 7. Log the ADMIN back in
      // We know this will work now because we verified the password in Step 2.
      try {
        await _auth.signInWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
      } catch (e) {
        // Edge case: Network error or rate limit right after creation
        return 'User created, but auto-login failed: ${e.toString()}';
      }

      notifyListeners();
      return null; // Success

    } catch (e) {
      notifyListeners();
      // Handle standard creation errors
      if (e.toString().contains('email-already-in-use')) {
        return 'Email already exists';
      }
      if (e.toString().contains('weak-password')) {
        return 'Password is too weak (minimum 6 characters)';
      }
      if (e.toString().contains('invalid-email')) {
        return 'Invalid email format';
      }
      return e.toString();
    }
  }

  /// NOTE: deleting an Auth user requires Admin SDK (backend).
  /// This deletes only the Firestore document, not the Auth account.
  Future<String?> requestDeleteAuthUser(String uid) async {
    try {
      final cur = currentUser;
      if (cur == null) return 'Not logged in';
      final curDoc = await _fire.collection('users').doc(cur.uid).get();
      final curRole = curDoc.data()?['role'] as String?;
      if (curRole != 'admin') return 'Permission denied. Only admins can delete users.';

      return 'Auth deletion requires Firebase Admin SDK. Use Firebase Console or implement cloud function.';
    } catch (e) {
      return e.toString();
    }
  }
}