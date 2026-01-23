import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a subject in the system
class Subject {
  final String id;
  final String name;
  final double price;
  final DateTime createdAt;
  final String? createdBy;
  final bool isActive;

  Subject({
    required this.id,
    required this.name,
    required this.price,
    required this.createdAt,
    this.createdBy,
    this.isActive = true,
  });

  factory Subject.fromMap(String id, Map<String, dynamic> map) {
    return Subject(
      id: id,
      name: map['name'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: map['createdBy'],
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'isActive': isActive,
    };
  }
}
