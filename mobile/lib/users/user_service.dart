import 'dart:convert';

import 'package:http/http.dart' as http;

import '../payments/payment_service.dart';

class UserProfile {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  UserProfile(this.firstName, this.lastName, this.email, this.phone);

  String get fullName => '$firstName $lastName'.trim();

  /// First letter of the first name plus first letter of the last name.
  String get initials {
    String first(String s) => s.isEmpty ? '' : s[0].toUpperCase();
    return first(firstName) + first(lastName);
  }
}

/// Talks to the backend /users endpoints. Display data only, no login.
class UserService {
  static const _base = PaymentService.baseUrl;

  Future<UserProfile> me() async {
    final res = await http.get(Uri.parse('$_base/users/me'));
    if (res.statusCode != 200) {
      throw Exception('Could not load profile (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return UserProfile(j['first_name'], j['last_name'], j['email'], j['phone']);
  }
}
