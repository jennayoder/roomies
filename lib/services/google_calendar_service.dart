import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../models/event.dart';

/// Handles Google Calendar OAuth and event CRUD.
///
/// Uses GoogleSignIn v7 singleton API:
///   - initialize() once at app start (or lazily here)
///   - attemptLightweightAuthentication() for silent re-auth
///   - authenticate() for interactive sign-in
///   - authorizeScopes() to get a calendar-scoped auth client
class GoogleCalendarService {
  static const _clientId =
      '1059067392660-cigc9c67r7h2g4l984ojspsk9iq79rqi.apps.googleusercontent.com';
  static const _calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// Returns an authenticated CalendarApi, or null if the user declines.
  /// GoogleSignIn.instance.initialize() must be called before this (done in main.dart).
  Future<gcal.CalendarApi?> _getApi() async {
    try {

      // Try silent first
      GoogleSignInAccount? account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      // Interactive if needed
      account ??= await GoogleSignIn.instance.authenticate();

      // Request calendar scope
      final auth = await account.authorizationClient
          .authorizeScopes([_calendarScope]);

      final httpClient = auth.authClient(scopes: [_calendarScope]);
      return gcal.CalendarApi(httpClient);
    } catch (e) {
      debugPrint('GoogleCalendarService._getApi error: $e');
      return null;
    }
  }

  /// Creates an event in the signed-in user's primary Google Calendar.
  /// Returns the Google Calendar event ID on success, null on failure.
  Future<String?> addEvent(Event event) async {
    try {
      final api = await _getApi();
      if (api == null) return null;

      final gcalEvent = gcal.Event(
        summary: event.title,
        description: event.description,
        location: event.location,
        start: gcal.EventDateTime(
          dateTime: event.dateTime.toUtc(),
          timeZone: 'America/Los_Angeles',
        ),
        end: gcal.EventDateTime(
          dateTime: event.dateTime.toUtc().add(const Duration(hours: 1)),
          timeZone: 'America/Los_Angeles',
        ),
      );

      final created = await api.events.insert(gcalEvent, 'primary');
      return created.id;
    } catch (e) {
      debugPrint('GoogleCalendarService.addEvent error: $e');
      return null;
    }
  }

  /// Deletes an event from the signed-in user's primary Google Calendar.
  Future<void> removeEvent(String calendarEventId) async {
    try {
      final api = await _getApi();
      if (api == null) return;
      await api.events.delete('primary', calendarEventId);
    } catch (e) {
      debugPrint('GoogleCalendarService.removeEvent error: $e');
    }
  }
}
