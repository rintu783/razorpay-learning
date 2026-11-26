import 'dart:convert';

import '../auth/api_client.dart';

class UserProfile {
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  UserProfile(this.email, this.firstName, this.lastName, this.phone);

  factory UserProfile.fromJson(Map<String, dynamic> j) =>
      UserProfile(j['email'], j['first_name'], j['last_name'], j['phone']);

  /// Empty until the user fills in their name on the profile screen.
  String get fullName => [firstName, lastName].where((p) => p != null && p.isNotEmpty).join(' ');

  /// What to show as the user's name: their name, or their email if they have not set one.
  String get displayName => fullName.isEmpty ? email : fullName;

  /// First letter of the first and last name, or the first letter of the email.
  String get initials {
    String first(String? s) => (s == null || s.isEmpty) ? '' : s[0].toUpperCase();
    final fromName = first(firstName) + first(lastName);
    return fromName.isNotEmpty ? fromName : first(email);
  }
}

/// Talks to the backend /users endpoints.
class UserService {
  ApiClient get _api => ApiClient.instance;

  Future<UserProfile> me() async {
    final res = await _api.get('/users/me');
    if (res.statusCode != 200) {
      throw ApiException('Could not load profile (${res.statusCode})', res.statusCode);
    }
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sends only the fields you pass. An empty string clears that field on the server.
  Future<UserProfile> updateProfile({String? firstName, String? lastName, String? phone}) async {
    final res = await _api.patch('/users/me', body: {
      'first_name': ?firstName,
      'last_name': ?lastName,
      'phone': ?phone,
    });
    if (res.statusCode != 200) {
      throw ApiException(ApiClient.errorMessage(res), res.statusCode);
    }
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
