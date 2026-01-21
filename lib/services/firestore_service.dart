import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> usersRef() {
    return _db.collection('users').withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => snap.data() ?? {},
      toFirestore: (data, _) => data,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserDoc(String uid) {
    return usersRef().doc(uid).get();
  }

  Future<void> setUserDoc(String uid, Map<String, dynamic> data) {
    return usersRef().doc(uid).set(data, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamUsers() {
    return usersRef().snapshots();
  }
}
