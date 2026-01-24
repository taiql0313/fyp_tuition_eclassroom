// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fire = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  AuthService() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<void> _logSystemEvent({
    required String type,
    required String category,
    required String action,
    required String user,
    required String role,
    String? userId,
    String? details,
    bool? success,
    Map<String, String>? clientContext,
  }) async {
    try {
      final payload = <String, dynamic>{
        'type': type,
        'category': category,
        'action': action,
        'user': user,
        'role': role,
        'userId': userId,
        'details': details ?? '',
        'success': success,
        'time': FieldValue.serverTimestamp(),
      };

      if (clientContext != null) {
        if ((clientContext['ipAddress'] ?? '').isNotEmpty) {
          payload['ipAddress'] = clientContext['ipAddress'];
        }
        if ((clientContext['device'] ?? '').isNotEmpty) {
          payload['device'] = clientContext['device'];
        }
        if ((clientContext['platform'] ?? '').isNotEmpty) {
          payload['platform'] = clientContext['platform'];
        }
        if ((clientContext['country'] ?? '').isNotEmpty) {
          payload['country'] = clientContext['country'];
        }
        if ((clientContext['region'] ?? '').isNotEmpty) {
          payload['region'] = clientContext['region'];
        }
        if ((clientContext['city'] ?? '').isNotEmpty) {
          payload['city'] = clientContext['city'];
        }
      }

      await _fire.collection('system_logs').add(payload);
    } catch (e) {
      // Logging should not break auth flow
      print('Error writing system log: $e');
    }
  }

  String _getPlatformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  Future<Map<String, String>> _getClientContext() async {
    final platform = _getPlatformLabel();
    String? ip;
    String? city;
    String? region;
    String? country;
    double? latitude;
    double? longitude;

    // ========== 1. TRY DEVICE GPS ==========
    if (!kIsWeb) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 5),
            );
            latitude = position.latitude;
            longitude = position.longitude;
            print('[AuthService] GPS: lat=$latitude, lon=$longitude');
          } else {
            print('[AuthService] Location permission denied: $permission');
          }
        } else {
          print('[AuthService] Location service not enabled');
        }
      } catch (e) {
        print('[AuthService] GPS error: $e');
      }
    }

    // ========== 2. REVERSE GEOCODE GPS COORDS ==========
    if (latitude != null && longitude != null) {
      try {
        final url =
            'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=en';
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          city = data['city']?.toString();
          if (city == null || city.isEmpty) {
            city = data['locality']?.toString();
          }
          region = data['principalSubdivision']?.toString();
          country = data['countryName']?.toString();
          print('[AuthService] Reverse geocode: city=$city, region=$region, country=$country');
        }
      } catch (e) {
        print('[AuthService] Reverse geocode error: $e');
      }
    }

    // ========== 3. FALLBACK: IP GEOLOCATION (multiple APIs) ==========
    // Try multiple APIs in case one is rate-limited or blocked
    final ipApis = [
      'https://ipapi.co/json/',
      'https://ipinfo.io/json',
      'https://ip-api.com/json/',
    ];

    for (final apiUrl in ipApis) {
      if (ip != null && ip!.isNotEmpty) break; // Already got IP
      try {
        final response = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          
          // Different APIs use different field names
          ip = data['ip']?.toString() ?? data['query']?.toString();
          
          // Only use IP-based location if we don't have GPS location
          if (city == null || city!.isEmpty) {
            city = data['city']?.toString();
          }
          if (region == null || region!.isEmpty) {
            region = data['region']?.toString() ?? data['regionName']?.toString();
          }
          if (country == null || country!.isEmpty) {
            country = data['country_name']?.toString() ?? 
                     data['country']?.toString() ??
                     data['countryName']?.toString();
          }
          print('[AuthService] IP API ($apiUrl): ip=$ip, city=$city, region=$region, country=$country');
        }
      } catch (e) {
        print('[AuthService] IP API ($apiUrl) error: $e');
      }
    }

    final result = <String, String>{
      'device': platform,
      'platform': platform,
    };
    
    if (ip != null && ip.isNotEmpty) result['ipAddress'] = ip;
    if (city != null && city.isNotEmpty) result['city'] = city;
    if (region != null && region.isNotEmpty) result['region'] = region;
    if (country != null && country.isNotEmpty) result['country'] = country;
    
    print('[AuthService] Final context: $result');
    return result;
  }

  Future<Map<String, String>> _getUserInfo(String uid, {String? fallback}) async {
    try {
      final doc = await _fire.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) {
        return {'name': fallback ?? uid, 'role': 'unknown'};
      }
      final name = data['displayName'] as String? ?? fallback ?? uid;
      final role = data['role'] as String? ?? 'user';
      return {'name': name, 'role': role};
    } catch (_) {
      return {'name': fallback ?? uid, 'role': 'unknown'};
    }
  }

  Future<void> _updateUserStatus(
    String uid, {
    bool? isOnline,
    bool updateLogin = false,
    bool updateLogout = false,
  }) async {
    try {
      final data = <String, dynamic>{
        'lastSeen': FieldValue.serverTimestamp(),
      };
      if (isOnline != null) data['isOnline'] = isOnline;
      if (updateLogin) data['lastLogin'] = FieldValue.serverTimestamp();
      if (updateLogout) data['lastLogout'] = FieldValue.serverTimestamp();
      await _fire.collection('users').doc(uid).update(data);
    } catch (e) {
      print('Error updating user status: $e');
    }
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final clientContext = await _getClientContext();
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

    await _updateUserStatus(uid, isOnline: true, updateLogin: true);
    await _logSystemEvent(
      type: 'Info',
      category: 'Authentication & Access',
      action: 'New User Registered',
      user: displayName,
      role: 'student',
      userId: uid,
      details: 'Account created successfully.',
      success: true,
      clientContext: clientContext,
    );

    notifyListeners();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final clientContext = await _getClientContext();
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      final user = _auth.currentUser;
      if (user != null) {
        await _updateUserStatus(user.uid, isOnline: true, updateLogin: true);
        final info = await _getUserInfo(user.uid, fallback: user.email);
        await _logSystemEvent(
          type: 'Info',
          category: 'Authentication & Access',
          action: 'User Login',
          user: info['name'] ?? user.email ?? user.uid,
          role: info['role'] ?? 'unknown',
          userId: user.uid,
          details: 'Login successful.',
          success: true,
          clientContext: clientContext,
        );
      }
      notifyListeners();
    } catch (e) {
      final clientContext = await _getClientContext();
      await _logSystemEvent(
        type: 'Error',
        category: 'Authentication & Access',
        action: 'Failed Login Attempt',
        user: email,
        role: 'unknown',
        details: e.toString(),
        success: false,
        clientContext: clientContext,
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      final info = await _getUserInfo(user.uid, fallback: user.email);
      final clientContext = await _getClientContext();
      await _updateUserStatus(user.uid, isOnline: false, updateLogout: true);
      await _logSystemEvent(
        type: 'Info',
        category: 'Authentication & Access',
        action: 'User Logout',
        user: info['name'] ?? user.email ?? user.uid,
        role: info['role'] ?? 'unknown',
        userId: user.uid,
        details: 'Logout successful.',
        success: true,
        clientContext: clientContext,
      );
    }
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

      final clientContext = await _getClientContext();
      await _logSystemEvent(
        type: 'Info',
        category: 'Authentication & Access',
        action: 'Admin Created User',
        user: currentAdmin.displayName ?? 'Admin',
        role: 'admin',
        userId: currentAdmin.uid,
        details: 'Created $displayName ($role)',
        success: true,
        clientContext: clientContext,
      );

      // 6. Sign out the NEW user
      await _auth.signOut();

      // 7. Log the ADMIN back in
      // We know this will work now because we verified the password in Step 2.
      try {
        await signInWithEmail(
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