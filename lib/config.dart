// config.dart - App Configuration

class AppConfig {
  static const String apiBaseUrl = 'https://att.igenhr.com/api';
  static const String screenshotUploadUrl = '$apiBaseUrl/screenshots/upload/';
  static const String checkInUrl = '$apiBaseUrl/attendance/checkin/';
  static const String checkOutUrl = '$apiBaseUrl/attendance/checkout/';
  static const String tasksUrl = '$apiBaseUrl/tasks/';
  static const String chatUsersUrl = 'https://att.igenhr.com/chat/api/users/';
  static const String chatConversationUrl = 'https://att.igenhr.com/chat/api/conversation/';
  static const int screenshotInterval = 30; // seconds
}

class AppColors {
  static const String bgDark = '#0a1628';
  static const String headerBlue = '#2196F3';
  static const String textWhite = '#FFFFFF';
  static const String textGray = '#8899aa';
  static const String green = '#4CD964';
  static const String orange = '#F5A623';
  static const String red = '#E74C3C';
  static const String purple = '#9B59B6';
  static const String navDark = '#0d1f35';
}
