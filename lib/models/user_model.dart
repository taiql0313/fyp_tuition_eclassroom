class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String role; // 'student' | 'teacher' | 'admin'
  final List<String> classIds;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.classIds = const [],
  });

  /// SAFE fromMap — handles string, empty, null, and list!!!!
  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final raw = map['classIds'];

    List<String> parsedClassIds;

    if (raw is List) {
      parsedClassIds = List<String>.from(raw);
    } else if (raw is String) {
      parsedClassIds = raw.isEmpty ? [] : [raw];
    } else {
      parsedClassIds = [];
    }

    return AppUser(
      uid: uid,
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      role: map['role'] ?? 'student',
      classIds: parsedClassIds,
    );
  }

  Map<String, dynamic> toMap() => {
    'email': email,
    'displayName': displayName,
    'role': role,
    'classIds': classIds,
  };
}
