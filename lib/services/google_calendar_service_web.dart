import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
import 'package:http/http.dart' as http;

import '../models/event.dart';

// ─── GIS JS interop ──────────────────────────────────────────────────────────

@JS('google.accounts.oauth2.initTokenClient')
external JSObject _initTokenClient(JSObject config);

// ─── Service ─────────────────────────────────────────────────────────────────

class GoogleCalendarService {
  static const _clientId =
      '1059067392660-cigc9c67r7h2g4l984ojspsk9iq79rqi.apps.googleusercontent.com';
  static const _calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// Uses the GIS token client to open an OAuth popup and get an access token.
  Future<String?> _getAccessToken() async {
    final completer = Completer<String?>();

    void callback(JSObject response) {
      final tokenJs = response['access_token'];
      if (tokenJs != null) {
        completer.complete((tokenJs as JSString).toDart);
      } else {
        final errJs = response['error'];
        final err = errJs != null ? (errJs as JSString).toDart : 'unknown';
        debugPrint('GIS token error: $err');
        completer.complete(null);
      }
    }

    final config = JSObject();
    config['client_id'] = _clientId.toJS;
    config['scope'] = _calendarScope.toJS;
    config['callback'] = callback.toJS;

    final tokenClient = _initTokenClient(config);
    tokenClient.callMethod('requestAccessToken'.toJS);

    return completer.future;
  }

  Future<gcal.CalendarApi?> _getApi() async {
    final token = await _getAccessToken();
    if (token == null) return null;

    final credentials = gapis.AccessCredentials(
      gapis.AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [_calendarScope],
    );

    final authClient = gapis.authenticatedClient(http.Client(), credentials);
    return gcal.CalendarApi(authClient);
  }

  /// Creates an event in the user's primary Google Calendar.
  /// Returns the Google Calendar event ID, or null on failure.
  Future<String?> addEvent(Event event) async {
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
  }

  /// Deletes an event from the user's primary Google Calendar.
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
