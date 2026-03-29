// config.dart - App Configuration

class AppConfig {
  static const String apiBaseUrl = 'http://127.0.0.1:8000/api';
  static const String screenshotUploadUrl = '$apiBaseUrl/screenshots/upload/';
  static const String checkInUrl = '$apiBaseUrl/attendance/checkin/';
  static const String checkOutUrl = '$apiBaseUrl/attendance/checkout/';
  static const String tasksUrl = '$apiBaseUrl/tasks/';
  static const String chatUsersUrl = '$apiBaseUrl/chat/users/';
  static const String chatConversationUrl = '$apiBaseUrl/chat/conversation/';
  static const String chatSendUrl = '$apiBaseUrl/chat/send/';
  static const String chatUnreadUrl = '$apiBaseUrl/chat/unread/';
  static const String chatMarkReadUrl = '$apiBaseUrl/chat/mark-read/';
  static const String chatOnlineUrl = '$apiBaseUrl/chat/online/';
  static const String chatMessageDetailUrl = '$apiBaseUrl/chat/messages/';
  static const String chatGroupsUrl = '$apiBaseUrl/chat/groups/';
  static const String profileUrl = '$apiBaseUrl/user/profile/';
  static const String uploadPhotoUrl = '$apiBaseUrl/user/upload-photo/';
  static const int screenshotInterval = 30; // seconds
}

class AppColors {
  static const String bgDark = '#0e2547ff';
  static const String headerBlue = '#2196F3';
  static const String textWhite = '#FFFFFF';
  static const String textGray = '#8899aa';
  static const String green = '#4CD964';
  static const String orange = '#F5A623';
  static const String red = '#E74C3C';
  static const String purple = '#9B59B6';
  static const String navDark = '#0d1f35';
}
