import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _col = 'users';

  /// Stream of AppUser list (keeps UI clean)
  Stream<List<AppUser>> streamUsers() {
    return _db
        .collection(_col)
        .snapshots()
        .map((snapshot) {
      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList();

      // Sort in memory instead of using orderBy to avoid index issues
      users.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

      return users;
    });
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _db.collection(_col).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  Future<void> updateUser({
    required String uid,
    required String displayName,
    required String role,
    List<String>? classIds,
  }) async {
    final Map<String, dynamic> data = {
      'displayName': displayName,
      'role': role,
    };

    if (classIds != null) {
      data['classIds'] = classIds;
    }

    await _db.collection(_col).doc(uid).update(data);
  }

  Future<void> createUserDoc(AppUser user) async {
    await _db.collection(_col).doc(user.uid).set(user.toMap());
  }

  /// Deletes only Firestore user document.
  Future<void> deleteUserFirestore(String uid) async {
    await _db.collection(_col).doc(uid).delete();
  }
}