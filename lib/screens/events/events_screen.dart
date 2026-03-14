import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/event.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _dateTimeFmt = DateFormat('EEE, MMM d · h:mm a');

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
      body: StreamBuilder<List<Event>>(
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
                      service: service,
                    )),
              ],
            ],
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

class _EventCard extends StatelessWidget {
  final Event event;
  final String currentUid;
  final String householdId;
  final FirestoreService service;

  const _EventCard({
    required this.event,
    required this.currentUid,
    required this.householdId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAttending = event.attendeeIds.contains(currentUid);

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
                    event.title,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outlined, color: colors.error),
                  onPressed: () =>
                      service.deleteEvent(householdId, event.id),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 14,
                    color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _dateTimeFmt.format(event.dateTime),
                  style: textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            if (event.location != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14,
                      color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    event.location!,
                    style: textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (event.description != null) ...[
              const SizedBox(height: 8),
              Text(
                event.description!,
                style: textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${event.attendeeIds.length} attending',
                  style: textTheme.labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const Spacer(),
                // Add to Google Calendar
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: 'Add to Google Calendar',
                  onPressed: () {
                    final uri = _googleCalendarUri(event);
                    // Use anchor-click approach — bypasses iOS popup blocker
                    final anchor = html.AnchorElement()
                      ..href = uri.toString()
                      ..target = '_blank'
                      ..rel = 'noopener noreferrer';
                    html.document.body?.append(anchor);
                    anchor.click();
                    anchor.remove();
                  },
                ),
                if (event.isUpcoming) ...[
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    onPressed: () => service.rsvpEvent(
                      householdId,
                      event.id,
                      !isAttending,
                    ),
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
