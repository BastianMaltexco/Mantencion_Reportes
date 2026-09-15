class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) =>
      AuthenticatedUser(
        id: json['id'] as int,
        username: json['username'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
      );

  final int id;
  final String username;
  final String fullName;
  final String role;

  bool get isAdministrator => role == 'Administrador';
}
