// lib/screens/student/student_chat_list.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/auth_service.dart';
import '../../services/student_teacher_chat_service.dart';
import '../chat/chat_screen.dart';

class StudentChatListPage extends StatefulWidget {
  const StudentChatListPage({super.key});

  @override
  State<StudentChatListPage> createState() => _StudentChatListPageState();
}

class _StudentChatListPageState extends State<StudentChatListPage> {
  final StudentTeacherChatService _chatService = StudentTeacherChatService();
  bool _isStartingNewChat = false;

  Future<void> _startNewChat() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;

    setState(() {
      _isStartingNewChat = true;
    });

    try {
      final teachers = await _chatService.getUsersForChat(user.uid, 'student');

      if (!mounted) return;

      if (teachers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No teachers available')),
        );
        return;
      }

      final selectedTeacher = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_add, color: Color(0xff1458a3), size: 24),
                    SizedBox(width: 12),
                    Text(
                      'Start New Chat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: teachers.length,
                  itemBuilder: (context, index) {
                    final teacher = teachers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(0xff1458a3).withOpacity(0.1),
                          child: Text(
                            teacher['name'].substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: Color(0xff1458a3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          teacher['name'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          teacher['email'],
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xff1458a3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Teacher',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff1458a3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.pop(context, teacher),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selectedTeacher != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        try {
          final chatId = await _chatService.startChat(
            studentId: user.uid,
            studentName: user.displayName ?? 'Student',
            teacherId: selectedTeacher['id'],
            teacherName: selectedTeacher['name'],
          );

          if (!mounted) return;

          Navigator.pop(context);

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                chatId: chatId,
                otherUserName: selectedTeacher['name'],
                otherUserRole: 'teacher',
                currentUserId: user.uid,
                userRole: 'student',
              ),
            ),
          );

          setState(() {});
        } catch (e) {
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error starting chat: $e')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStartingNewChat = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view chats')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Color(0xff1458a3),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (_isStartingNewChat)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _startNewChat,
              tooltip: 'Start new chat',
            ),
        ],
      ),
      body: Container(
        color: Colors.grey.shade50,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _chatService.getUserChats(user.uid, 'student'),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load chats',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xff1458a3),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final chats = snapshot.data ?? [];

            if (chats.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Color(0xff1458a3).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          size: 60,
                          color: Color(0xff1458a3),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No Conversations Yet',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start a conversation with your teachers',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: _isStartingNewChat ? null : _startNewChat,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xff1458a3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Start New Chat',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                final unreadCount = chat['unreadCount'] as int;
                final hasUnread = unreadCount > 0;
                final lastMessageIsMine = chat['lastMessageIsMine'] as bool;
                final lastMessage = chat['lastMessage'] as String;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Card(
                    elevation: hasUnread ? 2 : 0,
                    color: hasUnread ? Color(0xff1458a3).withOpacity(0.1) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: hasUnread ? Color(0xff1458a3).withOpacity(0.3) : Colors.grey.shade200,
                        width: hasUnread ? 1 : 0.5,
                      ),
                    ),
                    child: ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: Color(0xff1458a3),
                            child: Text(
                              (chat['otherName'] as String).substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (hasUnread)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chat['otherName'] as String,
                                    style: TextStyle(
                                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                                      color: hasUnread ? Color(0xff1458a3) : Colors.black87,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Color(0xff1458a3).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Teacher',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xff1458a3),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            timeago.format(chat['lastMessageTime'] as DateTime),
                            style: TextStyle(
                              fontSize: 11,
                              color: hasUnread ? Color(0xff1458a3) : Colors.grey.shade600,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            if (lastMessageIsMine)
                              const Icon(Icons.check_circle, size: 14, color: Colors.green),
                            if (lastMessageIsMine) const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                lastMessage.isNotEmpty ? lastMessage : 'Tap to start conversation',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: hasUnread ? Color(0xff1458a3) : Colors.grey.shade700,
                                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: hasUnread ? Color(0xff1458a3) : Colors.grey,
                        size: 20,
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatId: chat['chatId'] as String,
                              otherUserName: chat['otherName'] as String,
                              otherUserRole: 'teacher',
                              currentUserId: user.uid,
                              userRole: 'student',
                            ),
                          ),
                        );

                        if (mounted) {
                          setState(() {});
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isStartingNewChat ? null : _startNewChat,
        backgroundColor: Color(0xff1458a3),
        foregroundColor: Colors.white,
        elevation: 4,
        child: _isStartingNewChat
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.add_comment),
      ),
    );
  }
}