import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/picker_bottom_sheet.dart';
import '../widgets/setting_row.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<String> _dbPathFuture;

  @override
  void initState() {
    super.initState();
    _dbPathFuture = AppDatabase.instance.getDatabasePath();
  }

  void _showDatabasePath(BuildContext context, String dbPath) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Database Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Your custom words are stored here:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: SelectableText(
                dbPath,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dictionary data is read directly from the .dict file for better performance.',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Common',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8994A3),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SettingRow(
                  icon: Icons.language,
                  label: 'Language',
                  value: settings.language,
                  onTap: () => showPickerBottomSheet(
                    context: context,
                    title: 'Language',
                    options: SettingsProvider.languageOptions,
                    selected: settings.language,
                    onSelected: (String value) =>
                        context.read<SettingsProvider>().setLanguage(value),
                  ),
                ),
                const Divider(
                  indent: 52,
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F2F5),
                ),
                SettingRow(
                  icon: Icons.access_time,
                  label: 'Time to push',
                  value: settings.timeToPush,
                  onTap: () => showPickerBottomSheet(
                    context: context,
                    title: 'Time to push',
                    options: SettingsProvider.timeToPushOptions,
                    selected: settings.timeToPush,
                    onSelected: (String value) {
                      context.read<SettingsProvider>().setTimeToPush(value);
                      final int minutes = int.parse(value.split(' ').first);
                      context.read<PushProvider>().reschedule(minutes);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Database',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8994A3),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                InkWell(
                  onTap: () async {
                    final String dbPath = await _dbPathFuture;
                    if (mounted) {
                      _showDatabasePath(context, dbPath);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.storage,
                          color: Color(0xFF3B4957),
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Database Location',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF3B4957),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<String>(
                                future: _dbPathFuture,
                                builder:
                                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                                  if (snapshot.hasData) {
                                    final String fileName =
                                        snapshot.data!.split(Platform.pathSeparator).last;
                                    return Text(
                                      fileName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF8994A3),
                                      ),
                                    );
                                  }
                                  return const Text(
                                    'Loading...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF8994A3),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF8994A3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
