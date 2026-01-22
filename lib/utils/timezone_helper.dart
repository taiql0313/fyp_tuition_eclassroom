/// Helper class for Malaysia timezone (GMT+8)
class TimezoneHelper {
  static const int malaysiaOffsetHours = 8;

  /// Get current time in Malaysia (GMT+8)
  /// Returns a DateTime object that represents the current Malaysia time
  static DateTime getMalaysiaTime() {
    final now = DateTime.now().toUtc();
    // Malaysia is UTC+8, so add 8 hours to UTC
    return now.add(Duration(hours: malaysiaOffsetHours));
  }

  /// Convert any DateTime to Malaysia time for comparison
  /// This ensures we're comparing apples to apples
  static DateTime toMalaysiaTime(DateTime dateTime) {
    // If it's already UTC, just add the offset
    if (dateTime.isUtc) {
      return dateTime.add(Duration(hours: malaysiaOffsetHours));
    }
    // If it's local time, convert to UTC first, then add offset
    final utc = dateTime.toUtc();
    return utc.add(Duration(hours: malaysiaOffsetHours));
  }

  /// Create a DateTime object that represents a specific Malaysia time
  /// This creates a UTC DateTime that, when converted to Malaysia time, shows the specified time
  static DateTime createMalaysiaDateTime(int year, int month, int day, int hour, int minute) {
    // Create a UTC DateTime that represents the Malaysia time
    // If we want 8 PM Malaysia time, we store 12 PM UTC (8 PM - 8 hours = 12 PM)
    final utcTime = DateTime.utc(year, month, day, hour - malaysiaOffsetHours, minute);
    return utcTime;
  }

  /// Get today's day name in Malaysia time
  static String getTodayDayName() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final malaysiaTime = getMalaysiaTime();
    return days[malaysiaTime.weekday - 1];
  }

  /// Get the hour in Malaysia time from a DateTime
  static int getMalaysiaHour(DateTime dateTime) {
    final malaysiaTime = toMalaysiaTime(dateTime);
    return malaysiaTime.hour;
  }
}
