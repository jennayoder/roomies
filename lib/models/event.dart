import 'package:cloud_firestore/cloud_firestore.dart';

/// A household event or calendar item.
///
/// Stored at: /households/{householdId}/events/{eventId}
class Event {
  final String id;
  final String title;
  final String? description;
  final DateTime dateTime;

  /// Optional location string (address or place name).
  final String? location;

  /// UIDs of members who have RSVP'd as attending.
  final List<String> attendeeIds;

  /// UID of the member who created the event.
  final String createdById;

  final DateTime createdAt;

  /// Maps uid → Google Calendar event ID for members who have synced this event.
  final Map<String, String> calendarEventIds;

  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.dateTime,
    this.location,
    required this.attendeeIds,
    required this.createdById,
    required this.createdAt,
    this.calendarEventIds = const {},
  });

  bool get isUpcoming => dateTime.isAfter(DateTime.now());

  // ─── Firestore serialization ───────────────────────────────────────────────

  factory Event.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      title: data['title'] as String,
      description: data['description'] as String?,
      dateTime: (data['dateTime'] as Timestamp).toDate(),
      location: data['location'] as String?,
      attendeeIds: List<String>.from(data['attendeeIds'] as List? ?? []),
      createdById: data['createdById'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      calendarEventIds: (data['calendarEventIds'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'dateTime': Timestamp.fromDate(dateTime),
        'location': location,
        'attendeeIds': attendeeIds,
        'createdById': createdById,
        'createdAt': Timestamp.fromDate(createdAt),
        'calendarEventIds': calendarEventIds,
      };

  Event copyWith({
    List<String>? attendeeIds,
    Map<String, String>? calendarEventIds,
  }) =>
      Event(
        id: id,
        title: title,
        description: description,
        dateTime: dateTime,
        location: location,
        attendeeIds: attendeeIds ?? this.attendeeIds,
        createdById: createdById,
        createdAt: createdAt,
        calendarEventIds: calendarEventIds ?? this.calendarEventIds,
      );
}
