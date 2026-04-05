// test_api.dart - Simple API test

import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  print('🧪 Testing iGenHR API...\n');

  // Test login
  print('1️⃣ Testing login endpoint...');
  try {
    final response = await http
        .post(
          Uri.parse('https://att.igenhr.com/api/token/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': 'test@example.com',
            'password': 'testpass123'
          }),
        )
        .timeout(const Duration(seconds: 10));

    print('Status: ${response.statusCode}');
    print('Response: ${response.body}\n');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('✅ Login successful!');
      print('Token: ${data['access']}');
      print('User: ${data['user']}');
      print('Access granted: ${data['access_granted']}\n');

      // Test check-in with token
      print('2️⃣ Testing check-in endpoint...');
      final checkInResponse = await http
          .post(
            Uri.parse('https://att.igenhr.com/api/attendance/checkin/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${data['access']}'
            },
          )
          .timeout(const Duration(seconds: 10));

      print('Status: ${checkInResponse.statusCode}');
      print('Response: ${checkInResponse.body}\n');
    } else {
      print('❌ Login failed!');
      print('Response: ${response.body}\n');
    }
  } catch (e) {
    print('❌ Error: $e\n');
  }

  print('✅ Test complete!');
}
