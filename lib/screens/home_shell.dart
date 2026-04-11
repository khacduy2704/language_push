import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notification_service.dart';
import '../providers/word_provider.dart';
import '../widgets/word_form_dialog.dart';
import 'push_list_screen.dart';
import 'settings_screen.dart';
import 'world_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<String> _tabLabels = [
    'World',
    'List word to push',
    'Setting',
  ];

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermissions();
  }

  Future<void> _showAddWordDialog() async {
    final WordFormData? data = await showDialog<WordFormData>(
      context: context,
      builder: (_) => const WordFormDialog(
        title: 'Add Word',
        saveButtonText: 'Save',
      ),
    );
    if (data == null || !mounted) {
      return;
    }
    try {
      await context
          .read<WordProvider>()
          .addWord(data.word, data.partOfSpeech, data.meaning);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save word. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSettingTab = _selectedIndex == 2;

    return Scaffold(
      backgroundColor: const Color(0xFFE2E6EB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            isSettingTab ? const Color(0xFFE65A67) : const Color(0xFFE2E6EB),
        centerTitle: true,
        title: Text(
          _tabLabels[_selectedIndex],
          style: TextStyle(
            color: isSettingTab ? Colors.white : const Color(0xFF3B4957),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: _selectedIndex == 0
            ? <Widget>[
                IconButton(
                  onPressed: _showAddWordDialog,
                  icon:
                      const Icon(Icons.add, color: Color(0xFFE65A67), size: 30),
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          WorldScreen(),
          PushListScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (int index) => setState(() => _selectedIndex = index),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'World'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Setting'),
        ],
      ),
    );
  }
}
