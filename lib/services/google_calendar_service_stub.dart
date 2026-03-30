import '../models/event.dart';

/// Stub for non-web platforms. Google Calendar OAuth is web-only for now.
class GoogleCalendarService {
  Future<String?> addEvent(Event event) async => null;
  Future<void> removeEvent(String calendarEventId) async {}
}
