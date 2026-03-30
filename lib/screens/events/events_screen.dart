import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/event.dart';
import '../../models/household.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/household_service.dart';
import '../../utils/open_url.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _dateTimeFmt = DateFormat('EEE, MMM d · h:mm a');
final _dateFmt = DateFormat.yMMMd();

/// Builds a Google Calendar "add event" URL for [event].
/// Opens Google Calendar (web or app) with all fields pre-filled — no OAuth needed.
Uri _googleCalendarUri(Event event) {
  // Format: YYYYMMDDTHHmmssZ (UTC)
  String gcalDate(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}'
        'T${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}Z';
  }

  final start = gcalDate(event.dateTime);
  final end = gcalDate(event.dateTime.add(const Duration(hours: 1)));

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': event.title,
    'dates': '$start/$end',
    if (event.description != null && event.description!.isNotEmpty)
      'details': event.description!,
    if (event.location != null && event.location!.isNotEmpty)
      'location': event.location!,
  });
}

/// Events tab — household calendar / event list.
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user?.householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Events')),
            body: const EmptyState(
              icon: Icons.event_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }

        return _EventsContent(
          householdId: user!.householdId!,
          currentUid: auth.currentUser!.uid,
        );
      },
    );
  }
}

class _EventsContent extends StatelessWidget {
  final String householdId;
  final String currentUid;

  const _EventsContent({
    required this.householdId,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddEventSheet(context, householdId, currentUid, service),
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
      ),
      body: StreamBuilder<Household?>(
        stream: HouseholdService().householdStream(householdId),
        builder: (context, householdSnap) {
          final isOwner =
              householdSnap.data?.members[currentUid] == HouseholdRole.owner;

          return StreamBuilder<List<Event>>(
            stream: service.eventsStream(householdId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingWidget(message: 'Loading events…');
              }

              final events = snapshot.data ?? [];
              if (events.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_outlined,
                  title: 'No events yet',
                  subtitle: 'Tap "Add Event" to schedule something.',
                );
              }

              final upcoming = events.where((e) => e.isUpcoming).toList();
              final past = events.where((e) => !e.isUpcoming).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (upcoming.isNotEmpty) ...[
                    _sectionHeader(context, 'Upcoming'),
                    const SizedBox(height: 8),
                    ...upcoming.map((e) => _EventCard(
                          event: e,
                          currentUid: currentUid,
                          householdId: householdId,
                          isOwner: isOwner,
                          service: service,
                        )),
                  ],
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(context, 'Past'),
                    const SizedBox(height: 8),
                    ...past.map((e) => _EventCard(
                          event: e,
                          currentUid: currentUid,
                          householdId: householdId,
                          isOwner: isOwner,
                          service: service,
                        )),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _EventCard extends StatefulWidget {
  final Event event;
  final String currentUid;
  final String householdId;
  final bool isOwner;
  final FirestoreService service;

  const _EventCard({
    required this.event,
    required this.currentUid,
    required this.householdId,
    required this.isOwner,
    required this.service,
  });

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool _calendarLoading = false;

  Future<void> _handleRsvp(bool isAttending) async {
    setState(() => _calendarLoading = true);
    try {
      if (!isAttending) {
        // Trigger Google auth FIRST (before any awaits) to stay in gesture context
        final calendarService = GoogleCalendarService();

        // Save RSVP
        await widget.service.rsvpEvent(widget.householdId, widget.event.id, true);

        // Now add to calendar
        String? calendarEventId;
        String? calendarError;
        try {
          calendarEventId = await calendarService.addEvent(widget.event);
        } catch (e) {
          calendarError = e.toString();
        }

        if (calendarEventId != null) {
          await widget.service.setCalendarEventId(
              widget.householdId, widget.event.id, widget.currentUid, calendarEventId);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(calendarEventId != null
                ? "You're in! 🎉 Added to Google Calendar."
                : calendarError != null
                    ? "You're in! 🎉 (Calendar error: $calendarError)"
                    : "You're in! 🎉 (Couldn't connect to Google Calendar)"),
            duration: const Duration(seconds: 5),
          ));
        }
      } else {
        // Going from attending → not attending
        final existingCalendarId = widget.event.calendarEventIds[widget.currentUid];
        await widget.service.rsvpEvent(widget.householdId, widget.event.id, false);
        if (existingCalendarId != null) {
          final calendarService = GoogleCalendarService();
          await calendarService.removeEvent(existingCalendarId);
        }
        await widget.service.setCalendarEventId(
            widget.householdId, widget.event.id, widget.currentUid, null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from your calendar.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAttending = widget.event.attendeeIds.contains(widget.currentUid);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.event.title,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // Edit + delete for owner or creator
                if (widget.isOwner || widget.event.createdById == widget.currentUid) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit event',
                    onPressed: () => _showEditEventSheet(
                      context,
                      event: widget.event,
                      householdId: widget.householdId,
                      service: widget.service,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outlined, color: colors.error),
                    tooltip: 'Delete event',
                    onPressed: () => widget.service
                        .deleteEvent(widget.householdId, widget.event.id),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _dateTimeFmt.format(widget.event.dateTime),
                  style: textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            if (widget.event.location != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14,
                      color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    widget.event.location!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (widget.event.description != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.event.description!,
                style: textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${widget.event.attendeeIds.length} attending',
                  style: textTheme.labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const Spacer(),
                // Add to Google Calendar (manual URL open)
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: 'Add to Google Calendar',
                  onPressed: () => openUrl(_googleCalendarUri(widget.event)),
                ),
                if (widget.event.isUpcoming) ...[
                  const SizedBox(width: 4),
                  _calendarLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: () => _handleRsvp(isAttending),
                          child: Text(isAttending ? "Can't go" : "I'm in"),
                        ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add event sheet ──────────────────────────────────────────────────────────

// ─── Edit event sheet ─────────────────────────────────────────────────────────

Future<void> _showEditEventSheet(
  BuildContext context, {
  required Event event,
  required String householdId,
  required FirestoreService service,
}) async {
  final titleCtrl = TextEditingController(text: event.title);
  final descCtrl = TextEditingController(text: event.description ?? '');
  final locationCtrl = TextEditingController(text: event.location ?? '');
  DateTime selectedDate = event.dateTime;
  TimeOfDay selectedTime =
      TimeOfDay(hour: event.dateTime.hour, minute: event.dateTime.minute);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Event',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (d != null) setS(() => selectedDate = d);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(_dateFmt.format(selectedDate)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final t = await showTimePicker(
                  context: ctx,
                  initialTime: selectedTime,
                );
                if (t != null) setS(() => selectedTime = t);
              },
              icon: const Icon(Icons.access_time),
              label: Text(selectedTime.format(ctx)),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final dateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                await service.updateEvent(householdId, event.id, {
                  'title': title,
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'location': locationCtrl.text.trim().isEmpty
                      ? null
                      : locationCtrl.text.trim(),
                  'dateTime': Timestamp.fromDate(dateTime),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Add event sheet ──────────────────────────────────────────────────────────

Future<void> _showAddEventSheet(
  BuildContext context,
  String householdId,
  String currentUid,
  FirestoreService service,
) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Event',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Event title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 1)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setS(() => selectedDate = picked);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  selectedDate == null
                      ? 'Pick date *'
                      : DateFormat.yMMMd().format(selectedDate!),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.now(),
                  );
                  if (picked != null) setS(() => selectedTime = picked);
                },
                icon: const Icon(Icons.access_time),
                label: Text(
                  selectedTime == null
                      ? 'Pick time *'
                      : selectedTime!.format(ctx),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty ||
                      selectedDate == null ||
                      selectedTime == null) return;

                  final dateTime = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );

                  final event = Event(
                    id: const Uuid().v4(),
                    title: title,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    dateTime: dateTime,
                    location: locationCtrl.text.trim().isEmpty
                        ? null
                        : locationCtrl.text.trim(),
                    attendeeIds: [currentUid],
                    createdById: currentUid,
                    createdAt: DateTime.now(),
                  );
                  await service.addEvent(householdId, event);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
