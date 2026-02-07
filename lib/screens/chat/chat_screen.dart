// lib/screens/chat/chat_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../services/student_teacher_chat_service.dart';
import '../../utils/timezone_helper.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserRole; // 'student' or 'teacher'
  final String currentUserId;
  final String currentUserName;
  final String userRole; // 'student' or 'teacher'

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserRole,
    required this.currentUserId,
    required this.currentUserName,
    required this.userRole,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final StudentTeacherChatService _chatService = StudentTeacherChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  bool _isSending = false;
  bool _isUploading = false;
  bool _showEmojiPicker = false;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _chatStream;
  DateTime? _lastSeenMessage;

  static const List<String> _emojiList = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣',
    '🙂', '🙃', '😉', '😊', '😍', '😘', '😗', '😚',
    '😋', '😎', '🤩', '🥳', '😇', '🤗', '🤔', '🤨',
    '😐', '😑', '😶', '🙄', '😏', '😣', '😥', '😮',
    '🤐', '😯', '😪', '😫', '🥱', '😴', '😌', '😛',
    '😜', '😝', '🤪', '🤨', '🫣', '😳', '🥵', '🥶',
    '😡', '😠', '🤯', '😱', '😢', '😭', '😤', '😓',
    '🙏', '👍', '👎', '👏', '🔥', '✨', '💯', '❤️',
  ];

  @override
  void initState() {
    super.initState();
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();
      _scrollToBottom();
    });
    _updateLastSeen();
    _chatStream = FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _updateLastSeen();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _markAsRead() async {
    await _chatService.markAsRead(
      widget.chatId,
      widget.currentUserId,
      widget.userRole,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    // Use the other user's name from widget.otherUserName
    // When current user sends, we need to store their name too
    // For now, let's use a simple approach
    final senderDisplayName = widget.currentUserName.isNotEmpty
        ? widget.currentUserName
        : (widget.userRole == 'student' ? 'Student' : 'Teacher');

    _messageController.clear();

    try {
      await _chatService.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUserId,
        senderName: senderDisplayName, // This needs to be the actual name
        text: text,
        isStudent: widget.userRole == 'student',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _messageController.text = text;
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _toggleEmojiPicker() {
    FocusScope.of(context).unfocus();
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final insertAt = selection.isValid ? selection.start : text.length;
    final newText = text.replaceRange(
      insertAt,
      selection.isValid ? selection.end : text.length,
      emoji,
    );
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + emoji.length),
    );
  }

  Future<void> _initChatMeta() async {
    // no-op (kept for compatibility)
  }

  Future<void> _updateLastSeen() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .update({'lastSeen': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        widget.userRole == 'student' ? 'lastSeenStudent' : 'lastSeenTeacher': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isUploading) return;
    final picker = ImagePicker();
    // Prefer rear camera so emulator uses laptop webcam when AVD Back camera is set to Webcam0
    final XFile? picked = source == ImageSource.camera
        ? await picker.pickImage(
            source: source,
            imageQuality: 80,
            maxWidth: 1600,
            preferredCameraDevice: CameraDevice.rear,
          )
        : await picker.pickImage(
            source: source,
            imageQuality: 80,
            maxWidth: 1600,
          );
    if (picked == null) return;

    final fileName = picked.name;
    final fileSize = await File(picked.path).length();

    await _sendAttachmentMessage(
      messageType: 'image',
      fileName: fileName,
      filePath: picked.path,
      fileSize: fileSize,
      mimeType: fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
    );
  }

  Future<void> _pickFile() async {
    if (_isUploading) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    await _sendAttachmentMessage(
      messageType: 'file',
      fileName: file.name,
      filePath: file.path,
      fileBytes: file.bytes,
      fileSize: file.size,
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Attach File'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendAttachmentMessage({
    required String messageType,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    int? fileSize,
    String? mimeType,
  }) async {
    setState(() => _isUploading = true);

    final senderDisplayName = widget.currentUserName.isNotEmpty
        ? widget.currentUserName
        : (widget.userRole == 'student' ? 'Student' : 'Teacher');

    try {
      final fileUrl = await _chatService.uploadChatFile(
        chatId: widget.chatId,
        fileName: fileName,
        filePath: filePath,
        fileBytes: fileBytes,
        contentType: mimeType,
      );

      await _chatService.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUserId,
        senderName: senderDisplayName,
        text: '',
        isStudent: widget.userRole == 'student',
        messageType: messageType,
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send attachment: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open file')),
      );
    }
  }

  Widget _buildFirestoreImage(String fileRef) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _chatService.getChatFileFromFirestore(fileRef),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 220,
            height: 180,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        final data = snapshot.data!;
        final base64Data = data['fileData'] as String? ?? '';
        if (base64Data.isEmpty) {
          return Container(
            width: 220,
            height: 180,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
          );
        }
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          width: 220,
          height: 180,
          fit: BoxFit.cover,
        );
      },
    );
  }

  Future<void> _downloadFirestoreFile(String fileRef, String fallbackName) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      final data = await _chatService.getChatFileFromFirestore(fileRef);
      final base64Data = data['fileData'] as String? ?? '';
      if (base64Data.isEmpty) {
        throw Exception('File data missing');
      }
      final originalName = data['originalFileName'] as String?;
      final fileName = (originalName != null && originalName.isNotEmpty)
          ? originalName
          : fallbackName;
      final bytes = base64Decode(base64Data);
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await OpenFile.open(filePath);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildLastOnlineText() {
    if (_chatStream == null) {
      return const Text(
        'Last online: unknown',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final field = widget.userRole == 'student' ? 'lastSeenTeacher' : 'lastSeenStudent';
        final lastSeen = data?[field] as Timestamp?;
        if (lastSeen == null) {
          return const Text(
            'Last online: unknown',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          );
        }

        final lastSeenDate = lastSeen.toDate();
        final relative = timeago.format(lastSeenDate);
        return Text(
          'Last online: $relative',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        );
      },
    );
  }

  void _showChatOptions() {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: chatRef.get(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Chat Info'),
                    onTap: () {
                      Navigator.pop(context);
                      _showChatInfo(data);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.archive_outlined, color: Colors.red),
                    title: const Text('Archive Chat', style: TextStyle(color: Colors.red)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _hideChat();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChatInfo(Map<String, dynamic>? data) {
    final createdAt = (data?['createdAt'] as Timestamp?)?.toDate();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('With: ${widget.otherUserName}'),
            const SizedBox(height: 6),
            Text('Role: ${widget.otherUserRole.capitalize()}'),
            const SizedBox(height: 6),
            Text('Chat ID: ${widget.chatId}'),
            if (createdAt != null) ...[
              const SizedBox(height: 6),
              Text('Created: ${DateFormat('dd MMM yyyy').format(createdAt)}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _hideChat() async {
    final field = widget.userRole == 'student' ? 'hiddenForStudent' : 'hiddenForTeacher';
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      field: true,
    });
    if (!mounted) return;
    Navigator.pop(context);
  }

  String _formatTime(DateTime time) {
    final malaysiaTime = TimezoneHelper.toMalaysiaTime(time);
    final now = TimezoneHelper.getMalaysiaTime();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(malaysiaTime.year, malaysiaTime.month, malaysiaTime.day);

    if (today == messageDay) {
      return DateFormat('h:mm a').format(malaysiaTime);
    } else if (today.difference(messageDay).inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d').format(malaysiaTime);
    }
  }

  Widget _buildMessageContent(Map<String, dynamic> message, bool isMe) {
    final messageType = message['messageType'] as String? ?? 'text';
    final text = message['text'] as String? ?? '';
    final fileUrl = message['fileUrl'] as String?;
    final fileName = message['fileName'] as String? ?? 'File';
    final fileSize = message['fileSize'] as int?;
    final isFirestoreRef = fileUrl != null && fileUrl.startsWith('firestore:');

    if (messageType == 'image' && fileUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: isFirestoreRef
                ? _buildFirestoreImage(fileUrl)
                : Image.network(
                    fileUrl,
                    width: 220,
                    height: 180,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 220,
                        height: 180,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 220,
                        height: 180,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                      );
                    },
                  ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ],
      );
    }

    if (messageType == 'file' && fileUrl != null) {
      final sizeText = _formatFileSize(fileSize);
      return InkWell(
        onTap: () => isFirestoreRef
            ? _downloadFirestoreFile(fileUrl, fileName)
            : _openUrl(fileUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file,
              color: isMe ? Colors.white : Colors.blueGrey,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sizeText.isNotEmpty)
                    Text(
                      sizeText,
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      text,
      style: TextStyle(
        color: isMe ? Colors.white : Colors.black87,
        fontSize: 15,
        height: 1.4,
      ),
    );
  }

  Widget _buildMessageBubble(
      Map<String, dynamic> message,
      bool isMe,
      Map<String, dynamic>? previousMessage,
      ) {
    final timestamp = message['timestamp'] as DateTime;
    final malaysiaTimestamp = TimezoneHelper.toMalaysiaTime(timestamp);
    final timeText = _formatTime(malaysiaTimestamp);
    final showDate = _lastSeenMessage == null ||
        _lastSeenMessage!.day != malaysiaTimestamp.day ||
        _lastSeenMessage!.month != malaysiaTimestamp.month ||
        _lastSeenMessage!.year != malaysiaTimestamp.year;

    if (showDate) {
      _lastSeenMessage = malaysiaTimestamp;
    }

    // Check if we should show sender info for this message
    bool showSenderInfo = false;
    if (!isMe) {
      if (previousMessage == null) {
        // First message in the list
        showSenderInfo = true;
      } else {
        final previousIsMe = previousMessage['senderId'] == widget.currentUserId;
        if (previousIsMe) {
          // Previous message was from me, so show sender info for this other user's message
          showSenderInfo = true;
        } else {
          // Previous message was also from other user
          final previousSenderId = previousMessage['senderId'] as String;
          final currentSenderId = message['senderId'] as String;
          // Only show sender info if different sender
          showSenderInfo = previousSenderId != currentSenderId;
        }
      }
    }

    // Define colors as variables to avoid const context issues
    final otherRoleColor = widget.otherUserRole == 'teacher'
        ? const Color(0xFF1976D2) // Blue 700
        : const Color(0xFF2E7D32); // Green 700
    final otherRoleLightColor = widget.otherUserRole == 'teacher'
        ? const Color(0xFFBBDEFB) // Blue 100
        : const Color(0xFFC8E6C9); // Green 100

    // Use the consistent color for my messages
    final myMessageColor = const Color(0xff1458a3);

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showDate)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              DateFormat('EEEE, MMMM d, yyyy').format(malaysiaTimestamp),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(
            left: isMe ? 60 : 8,
            right: isMe ? 8 : 60,
            bottom: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSenderInfo)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Row(
                    children: [
                      // Use the actual name from widget.otherUserName when showing other user's messages
                      Text(
                        isMe ? 'You' : widget.otherUserName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xff1458a3).withOpacity(0.2) : otherRoleLightColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isMe ? widget.userRole.capitalize() : widget.otherUserRole.capitalize(),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? const Color(0xff1458a3) : otherRoleColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!isMe) const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? myMessageColor : Colors.grey.shade100,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _buildMessageContent(message, isMe),
                    ),
                  ),
                  if (isMe) const SizedBox(width: 8),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 0 : 12,
                  right: isMe ? 12 : 0,
                  top: 4,
                ),
                child: Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('h:mm a').format(malaysiaTimestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                    if (isMe && (message['isRead'] as bool? ?? false))
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.green,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = widget.userRole == 'student';
    final otherUserRoleLabel = widget.otherUserRole.capitalize();

    // Use the consistent color for the entire app
    final primaryColor = const Color(0xff1458a3);

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        foregroundColor: theme.appBarTheme.foregroundColor ?? Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Text(
                widget.otherUserName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          otherUserRoleLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                        const SizedBox(width: 8),
                        _buildLastOnlineText(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.getMessages(widget.chatId),
              initialData: const [],
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Failed to load messages'),
                  );
                }

                final messages = snapshot.data ?? [];

                _lastSeenMessage = null;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                if (messages.isEmpty) {
                  final emptyTheme = Theme.of(context);
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: emptyTheme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation with ${widget.otherUserName}',
                          style: TextStyle(
                            fontSize: 16,
                            color: emptyTheme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send your first message below',
                          style: TextStyle(
                            fontSize: 14,
                            color: emptyTheme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message['senderId'] == widget.currentUserId;
                    final previousMessage = index > 0 ? messages[index - 1] : null;
                    return _buildMessageBubble(message, isMe, previousMessage);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: theme.scaffoldBackgroundColor,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.emoji_emotions_outlined,
                                color: theme.colorScheme.onSurfaceVariant),
                            onPressed: _toggleEmojiPicker,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.attach_file,
                                color: theme.colorScheme.onSurfaceVariant),
                            onPressed: _isUploading ? null : _showAttachmentSheet,
                          ),
                          IconButton(
                            icon: Icon(Icons.camera_alt,
                                color: theme.colorScheme.onSurfaceVariant),
                            onPressed: _isUploading ? null : () => _pickImage(ImageSource.camera),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: (_isSending || _isUploading)
                          ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: (_isSending || _isUploading) ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showEmojiPicker)
            SizedBox(
              height: 260,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _emojiList.length,
                itemBuilder: (context, index) {
                  final emoji = _emojiList[index];
                  return InkWell(
                    onTap: () => _insertEmoji(emoji),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// Extension for capitalizing strings
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}