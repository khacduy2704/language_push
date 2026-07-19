import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../data/notification_service.dart';
import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/word_provider.dart';
import '../widgets/word_form_dialog.dart';
import 'practice_screen.dart';
import 'push_list_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'world_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool _notificationsEnabled = true;
  int _selectedIndex = 0;

  static const List<String> _tabLabels = [
    'World',
    'List word to push',
    'Search',
    'Setting',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.requestPermissions();
    _refreshNotificationPermissionStatus();
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

  Future<void> _showClearAllWordsDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove All Words'),
        content: const Text(
          'Are you sure you want to remove all words from World list?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF3B30),
            ),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final int intervalMinutes = context.read<SettingsProvider>().intervalMinutes;
      await context.read<WordProvider>().clearAllWords();
      await context.read<PushProvider>().clearAllWords(intervalMinutes);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All words removed from World list.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove all words.')),
      );
    }
  }

  void _onPracticePressed() {
    final List<Word> pushedWords = context.read<PushProvider>().pushedWords;
    if (pushedWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No words in push list to practice.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeScreen(words: List<Word>.of(pushedWords)),
      ),
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSettingTab = _selectedIndex == 3;

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
        actions: <Widget>[
          if (_selectedIndex == 0)
            IconButton(
              onPressed: _showClearAllWordsDialog,
              icon: const Icon(
                Icons.delete_sweep,
                color: Color(0xFFE65A67),
                size: 28,
              ),
            ),
          if (_selectedIndex == 0)
            IconButton(
              onPressed: _showAddWordDialog,
              icon: const Icon(Icons.add, color: Color(0xFFE65A67), size: 30),
            ),
          IconButton(
            onPressed: _signOut,
            tooltip: 'Sign out',
            icon: Icon(
              Icons.logout,
              color: isSettingTab ? Colors.white : const Color(0xFF3B4957),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          WorldScreen(),
          PushListScreen(),
          SearchScreen(),
          SettingsScreen(),
        ],
      ),
      floatingActionButton: _selectedIndex == 1
          ? ElevatedButton(
              onPressed: _onPracticePressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65A67),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Practice',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!_notificationsEnabled)
            Material(
              color: const Color(0xFFFFF4D6),
              child: InkWell(
                onTap: _openNotificationSettings,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.notifications_off_rounded,
                        color: Color(0xFF8A5B00),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notifications are off. Tap here to turn them on in app settings.',
                          style: TextStyle(
                            color: Color(0xFF8A5B00),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.open_in_new_rounded,
                        color: Color(0xFF8A5B00),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF3B4957),
            unselectedItemColor: const Color(0xFF8994A3),
            currentIndex: _selectedIndex,
            onTap: (int index) => setState(() => _selectedIndex = index),
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Word'),
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.settings), label: 'Setting'),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermissionStatus();
    }
  }

  Future<void> _refreshNotificationPermissionStatus() async {
    final PermissionStatus status = await Permission.notification.status;
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationsEnabled = status.isGranted;
    });
  }

  Future<void> _openNotificationSettings() async {
    await openAppSettings();
  }
}
