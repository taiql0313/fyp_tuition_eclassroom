// lib/services/student_teacher_chat_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class StudentTeacherChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // 1. Start or get existing chat
  Future<String> startChat({
    required String studentId,
    required String studentName,
    required String teacherId,
    required String teacherName,
    required bool startedByStudent,
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
        'hiddenForStudent': false,
        'hiddenForTeacher': false,
        'lastSeenStudent': startedByStudent ? FieldValue.serverTimestamp() : null,
        'lastSeenTeacher': startedByStudent ? null : FieldValue.serverTimestamp(),
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
    String messageType = 'text', // 'text', 'image', 'file'
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) async {
    try {
      String previewText;
      if (messageType == 'image') {
        previewText = '📷 Photo';
      } else if (messageType == 'file') {
        previewText = fileName != null && fileName.isNotEmpty ? '📎 $fileName' : '📎 File';
      } else {
        previewText = text.isNotEmpty ? text : 'Message';
      }

      // Add message to subcollection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'messageType': messageType,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
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
        'lastMessage': previewText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': senderId,
        'unreadCountStudent': isStudent ? currentUnreadStudent : currentUnreadStudent + 1,
        'unreadCountTeacher': isStudent ? currentUnreadTeacher + 1 : currentUnreadTeacher,
        'hiddenForStudent': false,
        'hiddenForTeacher': false,
        isStudent ? 'lastSeenStudent' : 'lastSeenTeacher': FieldValue.serverTimestamp(),
      });

      // Update sender last seen
      await _firestore.collection('users').doc(senderId).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });

      // Create notification for the receiver (teacher gets notified when student sends)
      if (isStudent) {
        final teacherId = data['teacherId'] as String?;
        final studentName = data['studentName'] as String? ?? 'A student';
        print('DEBUG: isStudent=$isStudent, teacherId=$teacherId, studentName=$studentName');
        if (teacherId != null && teacherId.isNotEmpty) {
          print('DEBUG: Creating notification for teacher $teacherId');
          try {
            await _notificationService.createForUser(
              userId: teacherId,
              type: 'message',
              title: 'New Message',
              message: '$studentName sent you a message',
            );
            print('DEBUG: Notification created successfully');
          } catch (e) {
            print('DEBUG: Error creating notification: $e');
          }
        } else {
          print('DEBUG: teacherId is null or empty, skipping notification');
        }
      }
    } catch (e) {
      print('StudentTeacherChatService Error (sendMessage): $e');
      rethrow;
    }
  }

  Future<String> uploadChatFile({
    required String chatId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    String? contentType,
  }) async {
    try {
      final File? file = filePath != null ? File(filePath) : null;
      if (fileBytes == null && file == null) {
        throw Exception('No file data provided');
      }

      final Uint8List bytes = fileBytes ?? await file!.readAsBytes();
      const maxSize = 1024 * 1024; // 1MB
      if (bytes.length > maxSize) {
        throw Exception('File too large. Max size is 1MB.');
      }

      final base64String = base64Encode(bytes);
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storedFileName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';

      final docRef = await _firestore.collection('chat_files').add({
        'chatId': chatId,
        'fileName': storedFileName,
        'originalFileName': fileName,
        'fileData': base64String,
        'fileSize': bytes.length,
        'contentType': contentType,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      return 'firestore:${docRef.id}';
    } catch (e) {
      throw Exception('Error processing file: $e');
    }
  }

  Future<Map<String, dynamic>> getChatFileFromFirestore(String fileRef) async {
    if (!fileRef.startsWith('firestore:')) {
      throw Exception('Invalid file reference format');
    }
    final docId = fileRef.replaceFirst('firestore:', '');
    final doc = await _firestore.collection('chat_files').doc(docId).get();
    if (!doc.exists) {
      throw Exception('File not found in Firestore');
    }
    final data = doc.data()!;
    return {
      'fileName': data['fileName'] ?? '',
      'originalFileName': data['originalFileName'] ?? '',
      'fileData': data['fileData'] ?? '',
      'fileSize': data['fileSize'] ?? 0,
      'contentType': data['contentType'],
    };
  }

  // 3. Get all chats for user with unread counts
  Stream<List<Map<String, dynamic>>> getUserChats(String userId, String role) {
    final field = role == 'student' ? 'studentId' : 'teacherId';
    final unreadField = role == 'student' ? 'unreadCountStudent' : 'unreadCountTeacher';

    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      final List<Map<String, dynamic>> chats = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final hiddenForStudent = data['hiddenForStudent'] == true;
        final hiddenForTeacher = data['hiddenForTeacher'] == true;

        if (role == 'student' && hiddenForStudent) {
          continue;
        }
        if (role == 'teacher' && hiddenForTeacher) {
          continue;
        }

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

      // Sort in memory to avoid composite index requirements
      chats.sort((a, b) {
        final aTime = a['lastMessageTime'] as DateTime;
        final bTime = b['lastMessageTime'] as DateTime;
        return bTime.compareTo(aTime);
      });

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
          'messageType': data['messageType'] as String? ?? 'text',
          'fileUrl': data['fileUrl'] as String?,
          'fileName': data['fileName'] as String?,
          'fileSize': data['fileSize'] as int?,
          'mimeType': data['mimeType'] as String?,
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
        role == 'student' ? 'lastSeenStudent' : 'lastSeenTeacher': FieldValue.serverTimestamp(),
      });

      // Mark all unread messages as read
      final messages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .get();

      if (messages.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in messages.docs) {
          final data = doc.data();
          final senderId = data['senderId'] as String? ?? '';
          if (senderId != currentUserId) {
            batch.update(doc.reference, {'isRead': true});
          }
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