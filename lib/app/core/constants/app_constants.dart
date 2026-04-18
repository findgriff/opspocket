/// App-wide constants kept out of scattered magic numbers.
class AppConstants {
  AppConstants._();

  static const String appName = 'OpsPocket';
  static const Duration sshConnectTimeout = Duration(seconds: 15);
  static const Duration sshCommandTimeout = Duration(seconds: 60);
  static const int defaultLogLines = 200;
  static const int auditSummaryMaxChars = 500;
  static const int outputDisplayMaxChars = 100 * 1024; // 100 KB
  static const String digitalOceanBaseUrl = 'https://api.digitalocean.com/v2';
  static const Duration providerHttpTimeout = Duration(seconds: 20);
  static const String freeTierServerLimit = '1 saved server on free tier';
  // App lock
  static const Duration defaultLockTimeout = Duration(minutes: 5);
}
