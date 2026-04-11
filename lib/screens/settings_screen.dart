import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/picker_bottom_sheet.dart';
import '../widgets/setting_row.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
      ],
    );
  }
}
