import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart' hide isSameDay;

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../core/theme/app_styles.dart';
import '../../core/utils/date_utils.dart' as du;
import '../tasks/task_editor_sheet.dart';
import '../tasks/task_tile.dart';

/// Month / 2-week / week calendar with dots on days that have tasks due and
/// an agenda for the selected day underneath.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = du.dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final month = DateTime(_focusedDay.year, _focusedDay.month);
    final byDay = ref.watch(calendarTasksProvider(month)).valueOrNull ?? {};
    final selectedTasks = byDay[_selectedDay] ?? const <Task>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar-fab',
        tooltip: 'New task on ${du.formatDue(_selectedDay)}',
        onPressed: () => showTaskEditor(context,
            initialDueDate: _selectedDay.add(const Duration(hours: 9))),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          TableCalendar<Task>(
            firstDay: DateTime(2000),
            lastDay: DateTime(2100),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => du.isSameDay(day, _selectedDay),
            calendarFormat: _format,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Month',
              CalendarFormat.twoWeeks: '2 weeks',
              CalendarFormat.week: 'Week',
            },
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: (day) => byDay[du.dateOnly(day)] ?? const [],
            onDaySelected: (selected, focused) => setState(() {
              _selectedDay = du.dateOnly(selected);
              _focusedDay = focused;
            }),
            onFormatChanged: (format) => setState(() => _format = format),
            onPageChanged: (focused) => setState(() => _focusedDay = focused),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              todayTextStyle:
                  TextStyle(color: theme.colorScheme.onPrimaryContainer),
              selectedDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SectionLabel(du.formatDayHeader(_selectedDay),
                  padding: EdgeInsets.zero),
            ),
          ),
          Expanded(
            child: selectedTasks.isEmpty
                ? Center(
                    child: Text(
                      'Nothing due this day',
                      style: theme.textTheme.bodyMedium!
                          .copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView(
                    children: [
                      for (final task in selectedTasks)
                        TaskTile(task: task, showDue: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
