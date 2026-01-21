// lib/services/student_teacher_chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentTeacherChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. Start or get existing chat
  Future<String> startChat({
    required String studentId,
    required String studentName,
    required String teacherId,
    required String teacherName,
  }) async {
    try {
      // Check if chat already exists
      final query = await _firestore
          .collection('chats')
          .where('studentId', isEqualTo: studentId)
          .where('teacherId', isEqualTo: teacherId)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return query.docs.first.id;
      }

      // Create new chat
      final chatRef = await _firestore.collection('chats').add({
        'studentId': studentId,
        'studentName': studentName,
        'teacherId': teacherId,
        'teacherName': teacherName,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': '',
        'unreadCountStudent': 0,
        'unreadCountTeacher': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return chatRef.id;
    } catch (e) {
      print('StudentTeacherChatService Error (startChat): $e');
      rethrow;
    }
  }

  // 2. Send message with unread tracking
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isStudent, // true if sender is student
  }) async {
    try {
      // Add message to subcollection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // Get current chat to update unread counts
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final data = chatDoc.data() as Map<String, dynamic>;
      final currentUnreadStudent = data['unreadCountStudent'] as int? ?? 0;
      final currentUnreadTeacher = data['unreadCountTeacher'] as int? ?? 0;

      // Update chat with last message and increment unread count for receiver
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unreadCountStudent': isStudent ? currentUnreadStudent : currentUnreadStudent + 1,
        'unreadCountTeacher': isStudent ? currentUnreadTeacher + 1 : currentUnreadTeacher,
      });
    } catch (e) {
      print('StudentTeacherChatService Error (sendMessage): $e');
      rethrow;
    }
  }

  // 3. Get all chats for user with unread counts
  Stream<List<Map<String, dynamic>>> getUserChats(String userId, String role) {
    final field = role == 'student' ? 'studentId' : 'teacherId';
    final unreadField = role == 'student' ? 'unreadCountStudent' : 'unreadCountTeacher';

    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final List<Map<String, dynamic>> chats = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final lastMessageTime = data['lastMessageTime'];
        final lastSenderId = data['lastSenderId'] as String? ?? '';

        chats.add({
          'chatId': doc.id,
          'otherName': role == 'student'
              ? (data['teacherName'] as String? ?? 'Teacher')
              : (data['studentName'] as String? ?? 'Student'),
          'lastMessage': data['lastMessage'] as String? ?? '',
          'lastMessageTime': lastMessageTime != null
              ? (lastMessageTime as Timestamp).toDate()
              : DateTime.now(),
          'unreadCount': data[unreadField] as int? ?? 0,
          'lastMessageIsMine': lastSenderId == userId,
        });
      }

      return chats;
    })
        .handleError((error) {
      print('StudentTeacherChatService Stream Error (getUserChats): $error');
      return <Map<String, dynamic>>[];
    });
  }

  // 4. Get messages for a chat
  Stream<List<Map<String, dynamic>>> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .asyncMap((snapshot) async {
      final List<Map<String, dynamic>> messages = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        messages.add({
          'id': doc.id,
          'senderId': data['senderId'] as String? ?? '',
          'senderName': data['senderName'] as String? ?? 'User',
          'text': data['text'] as String? ?? '',
          'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'isRead': data['isRead'] as bool? ?? false,
        });
      }

      return messages;
    })
        .handleError((error) {
      print('StudentTeacherChatService Stream Error (getMessages): $error');
      return <Map<String, dynamic>>[];
    });
  }

  // 5. Mark ALL messages as read and reset unread count
  Future<void> markAsRead(String chatId, String currentUserId, String role) async {
    try {
      final unreadField = role == 'student' ? 'unreadCountStudent' : 'unreadCountTeacher';

      // Reset unread count in chat document
      await _firestore.collection('chats').doc(chatId).update({
        unreadField: 0,
      });

      // Mark all unread messages as read
      final messages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (messages.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in messages.docs) {
          batch.update(doc.reference, {'isRead': true});
        }
        await batch.commit();
      }
    } catch (e) {
      print('StudentTeacherChatService Error (markAsRead): $e');
      // Not critical, ignore error
    }
  }

  // 6. Get all users for new chat
  Future<List<Map<String, dynamic>>> getUsersForChat(String currentUserId, String role) async {
    final oppositeRole = role == 'student' ? 'teacher' : 'student';

    try {
      final users = await _firestore
          .collection('users')
          .where('role', isEqualTo: oppositeRole)
          .get();

      final List<Map<String, dynamic>> userList = [];

      for (var doc in users.docs) {
        final data = doc.data() as Map<String, dynamic>;
        userList.add({
          'id': doc.id,
          'name': data['displayName'] as String? ?? data['name'] as String? ?? 'User',
          'email': data['email'] as String? ?? '',
        });
      }

      return userList;
    } catch (e) {
      print('StudentTeacherChatService Error (getUsersForChat): $e');
      return [];
    }
  }
  // 7. Get user role from Firestore
  Future<String> getUserRole(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return (userDoc.data() as Map<String, dynamic>)['role'] as String? ?? 'user';
      }
      return 'user';
    } catch (e) {
      print('StudentTeacherChatService Error (getUserRole): $e');
      return 'user';
    }
  }

// 8. Get user details with role
  Future<Map<String, dynamic>> getUserDetails(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        return {
          'id': userId,
          'name': data['displayName'] as String? ?? data['name'] as String? ?? 'User',
          'email': data['email'] as String? ?? '',
          'role': data['role'] as String? ?? 'user',
          'photoUrl': data['photoUrl'] as String? ?? '',
        };
      }
      return {
        'id': userId,
        'name': 'User',
        'email': '',
        'role': 'user',
        'photoUrl': '',
      };
    } catch (e) {
      print('StudentTeacherChatService Error (getUserDetails): $e');
      return {
        'id': userId,
        'name': 'User',
        'email': '',
        'role': 'user',
        'photoUrl': '',
      };
    }
  }
}