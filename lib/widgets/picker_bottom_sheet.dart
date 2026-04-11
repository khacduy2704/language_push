import 'package:flutter/material.dart';

Future<void> showPickerBottomSheet({
  required BuildContext context,
  required String title,
  required List<String> options,
  required String selected,
  required ValueChanged<String> onSelected,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFC5CCD5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B4957),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 1, color: Color(0xFFC5CCD5)),
            ...options.map((String option) {
              final bool isSelected = option == selected;
              return ListTile(
                title: Text(
                  option,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFFE65A67)
                        : const Color(0xFF3B4957),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Color(0xFFE65A67))
                    : null,
                onTap: () {
                  onSelected(option);
                  Navigator.of(sheetContext).pop();
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
