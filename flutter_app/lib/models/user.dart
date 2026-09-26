class AppUser {
  final int id;
  final String name;
  final String phone;
  final String role; // 'admin' | 'worker'

  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
      };
}
