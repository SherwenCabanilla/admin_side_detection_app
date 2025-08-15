import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

Future<DateTimeRange?> pickDateRangeWithSf(
  BuildContext context, {
  DateTimeRange? initial,
}) async {
  DateTime? start = initial?.start;
  DateTime? end = initial?.end;
  String formatMdy(DateTime d) => '${d.month} ${d.day} ${d.year}';
  final TextEditingController startController = TextEditingController(
    text: start != null ? formatMdy(start) : '',
  );
  final TextEditingController endController = TextEditingController(
    text: end != null ? formatMdy(end) : '',
  );
  DateTime? parseMdy(String input) {
    final regex = RegExp(
      r'^\s*(\d{1,2})[\/\-\s]+(\d{1,2})[\/\-\s]+(\d{4})\s*$',
    );
    final m = regex.firstMatch(input);
    if (m == null) return null;
    final mm = int.tryParse(m.group(1)!);
    final dd = int.tryParse(m.group(2)!);
    final yyyy = int.tryParse(m.group(3)!);
    if (mm == null || dd == null || yyyy == null) return null;
    return DateTime(yyyy, mm, dd);
  }

  void syncControllersFromSelection() {
    if (start != null) startController.text = formatMdy(start!);
    if (end != null) endController.text = formatMdy(end!);
  }

  return showDialog<DateTimeRange>(
    context: context,
    builder:
        (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder:
                    (setStateCtx, setState) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        SfDateRangePicker(
                          selectionMode: DateRangePickerSelectionMode.range,
                          initialSelectedRange: PickerDateRange(start, end),
                          onSelectionChanged: (args) {
                            if (args.value is PickerDateRange) {
                              final r = args.value as PickerDateRange;
                              start = r.startDate;
                              end = r.endDate;
                              syncControllersFromSelection();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: startController,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Start (MM DD YYYY)',
                                  hintText: '8 14 2024',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  errorText:
                                      (startController.text.isEmpty)
                                          ? null
                                          : (parseMdy(
                                                    startController.text.trim(),
                                                  ) ==
                                                  null
                                              ? 'Invalid date'
                                              : null),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: endController,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'End (MM DD YYYY)',
                                  hintText: '5 15 2025',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  errorText:
                                      (endController.text.isEmpty)
                                          ? null
                                          : (parseMdy(
                                                    endController.text.trim(),
                                                  ) ==
                                                  null
                                              ? 'Invalid date'
                                              : null),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                // Prefer typed fields if provided
                                final typedStart = startController.text.trim();
                                final typedEnd = endController.text.trim();
                                final parsedStart = parseMdy(typedStart);
                                final parsedEnd = parseMdy(typedEnd);
                                // Validation: both fields must parse
                                if (typedStart.isNotEmpty &&
                                    parsedStart == null) {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (_) => const AlertDialog(
                                          title: Text('Invalid start date'),
                                          content: Text(
                                            'Use MM DD YYYY (e.g., 8 14 2024).',
                                          ),
                                        ),
                                  );
                                  return;
                                }
                                if (typedEnd.isNotEmpty && parsedEnd == null) {
                                  await showDialog(
                                    context: context,
                                    builder:
                                        (_) => const AlertDialog(
                                          title: Text('Invalid end date'),
                                          content: Text(
                                            'Use MM DD YYYY (e.g., 5 15 2025).',
                                          ),
                                        ),
                                  );
                                  return;
                                }
                                if (parsedStart != null) start = parsedStart;
                                if (parsedEnd != null) end = parsedEnd;
                                if (start != null && end != null) {
                                  // Ensure start <= end
                                  if (end!.isBefore(start!)) {
                                    await showDialog(
                                      context: context,
                                      builder:
                                          (_) => const AlertDialog(
                                            title: Text('Invalid range'),
                                            content: Text(
                                              'End date must be on or after start date.',
                                            ),
                                          ),
                                    );
                                    return;
                                  }
                                  Navigator.pop(
                                    context,
                                    DateTimeRange(
                                      start: DateTime(
                                        start!.year,
                                        start!.month,
                                        start!.day,
                                      ),
                                      end: DateTime(
                                        end!.year,
                                        end!.month,
                                        end!.day,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Apply'),
                            ),
                          ],
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
  );
}
