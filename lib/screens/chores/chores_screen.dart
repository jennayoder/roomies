import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/chore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';

final _dateFmt = DateFormat.yMMMd();

/// Chores tab — lists household tasks with completion status.
class ChoresScreen extends StatelessWidget {
  const ChoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return StreamBuilder(
      stream: auth.userProfileStream(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user?.householdId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chores')),
            body: const EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No household',
              subtitle: 'Join or create a household from the Home tab.',
            ),
          );
        }

        return _ChoresContent(
          householdId: user!.householdId!,
          currentUid: auth.currentUser!.uid,
        );
      },
    );
  }
}

class _ChoresContent extends StatelessWidget {
  final String householdId;
  final String currentUid;

  const _ChoresContent({
    required this.householdId,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Chores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddChoreSheet(context, householdId, currentUid, service),
        icon: const Icon(Icons.add),
        label: const Text('Add Chore'),
      ),
      body: StreamBuilder<List<Chore>>(
        stream: service.choresStream(householdId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: 'Loading chores…');
          }

          final chores = snapshot.data ?? [];
          if (chores.isEmpty) {
            return const EmptyState(
              icon: Icons.checklist_outlined,
              title: 'No chores yet',
              subtitle: 'Tap "Add Chore" to assign a task.',
            );
          }

          final pending = chores.where((c) => !c.isCompleted).toList();
          final done = chores.where((c) => c.isCompleted).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionHeader(context, 'To do'),
                const SizedBox(height: 8),
                ...pending.map((c) => _ChoreCard(
                      chore: c,
                      householdId: householdId,
                      service: service,
                    )),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionHeader(context, 'Done'),
                const SizedBox(height: 8),
                ...done.map((c) => _ChoreCard(
                      chore: c,
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

class _ChoreCard extends StatelessWidget {
  final Chore chore;
  final String householdId;
  final FirestoreService service;

  const _ChoreCard({
    required this.chore,
    required this.householdId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: chore.isCompleted,
          onChanged: (v) => service.toggleChoreComplete(
            householdId,
            chore.id,
            v ?? false,
          ),
        ),
        title: Text(
          chore.title,
          style: chore.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          [
            chore.frequency.label,
            if (chore.dueDate != null) 'Due ${_dateFmt.format(chore.dueDate!)}',
            if (chore.description != null) chore.description!,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outlined, color: colors.error),
          onPressed: () =>
              service.deleteChore(householdId, chore.id),
        ),
      ),
    );
  }
}

// ─── Add chore sheet ──────────────────────────────────────────────────────────

Future<void> _showAddChoreSheet(
  BuildContext context,
  String householdId,
  String currentUid,
  FirestoreService service,
) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  ChoreFrequency selectedFrequency = ChoreFrequency.once;
  DateTime? dueDate;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add Chore',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Chore title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ChoreFrequency>(
              value: selectedFrequency,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              items: ChoreFrequency.values
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.label),
                      ))
                  .toList(),
              onChanged: (v) => setS(() => selectedFrequency = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setS(() => dueDate = picked);
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                dueDate == null
                    ? 'Pick due date (optional)'
                    : 'Due: ${_dateFmt.format(dueDate!)}',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;

                final chore = Chore(
                  id: const Uuid().v4(),
                  title: title,
                  description:
                      descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  assignedToId: currentUid,
                  frequency: selectedFrequency,
                  dueDate: dueDate,
                  createdAt: DateTime.now(),
                );
                await service.addChore(householdId, chore);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
