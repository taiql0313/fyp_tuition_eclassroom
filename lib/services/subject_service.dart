import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/models/subject_model.dart';

class SubjectService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String _collection = 'subjects';

  /// Get all active subjects
  Stream<List<Subject>> streamSubjects() {
    return _db
        .collection(_collection)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final subjects = snapshot.docs
              .map((doc) => Subject.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by name in memory
          subjects.sort((a, b) => a.name.compareTo(b.name));
          return subjects;
        });
  }

  /// Get all subjects (including inactive) - for admin
  Stream<List<Subject>> streamAllSubjects() {
    return _db
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
          final subjects = snapshot.docs
              .map((doc) => Subject.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by name in memory
          subjects.sort((a, b) => a.name.compareTo(b.name));
          return subjects;
        });
  }

  /// Get a single subject by ID
  Future<Subject?> getSubject(String subjectId) async {
    try {
      final doc = await _db.collection(_collection).doc(subjectId).get();
      if (doc.exists) {
        return Subject.fromMap(doc.id, doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching subject: $e');
      return null;
    }
  }

  /// Create a new subject (admin only)
  Future<Subject> createSubject({
    required String name,
    required double price,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Check if user is admin
    final userDoc = await _db.collection('users').doc(user.uid).get();
    if (!userDoc.exists) {
      throw Exception('User not found');
    }
    final userData = userDoc.data()!;
    final userRole = userData['role'] as String?;
    if (userRole != 'admin') {
      throw Exception('Only admins can create subjects');
    }

    // Check if subject with same name already exists
    final existing = await _db
        .collection(_collection)
        .where('name', isEqualTo: name)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Subject with name "$name" already exists');
    }

    final subject = Subject(
      id: '',
      name: name,
      price: price,
      createdAt: DateTime.now(),
      createdBy: user.uid,
      isActive: true,
    );

    final docRef = await _db.collection(_collection).add(subject.toMap());
    return Subject.fromMap(docRef.id, subject.toMap());
  }

  /// Update a subject
  Future<void> updateSubject({
    required String subjectId,
    String? name,
    double? price,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    
    if (name != null) updates['name'] = name;
    if (price != null) updates['price'] = price;
    if (isActive != null) updates['isActive'] = isActive;

    if (updates.isEmpty) return;

    await _db.collection(_collection).doc(subjectId).update(updates);
  }

  /// Delete a subject (soft delete by setting isActive to false)
  Future<void> deleteSubject(String subjectId) async {
    await _db.collection(_collection).doc(subjectId).update({
      'isActive': false,
    });
  }
}
