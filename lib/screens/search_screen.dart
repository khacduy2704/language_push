import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/dictionary_file_search.dart';
import 'word_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AppDatabase _db = AppDatabase.instance;
  final DictionaryFileSearch _dictSearch = DictionaryFileSearch();

  List<dynamic> _results = <dynamic>[];
  bool _isLoading = false;
  bool _dictReady = false;
  String _initStatus = '';
  bool _hasShownReadyToast = false;
  Timer? _searchDebounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _initStatus =
          'Preparing offline dictionary...\nFirst run may take 10-30 seconds.';
    });

    try {
      await _dictSearch.ensureReady();
      if (!mounted) return;
      setState(() {
        _dictReady = true;
        _initStatus = '';
      });

      if (!_hasShownReadyToast && mounted) {
        _hasShownReadyToast = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline dictionary is ready.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await _loadWords();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dictReady = false;
        _initStatus = 'Could not prepare dictionary. Please reopen Search.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      _loadWords(query);
    });
  }

  Future<void> _loadWords([String query = '']) async {
    final int token = ++_searchToken;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final String normalizedQuery = query.trim();

      // Load custom words
      final List<Word> customWords =
          await _db.getWords(query: normalizedQuery, includePushed: false);

      // Load dictionary words using local random-access index.
      final List<DictWord> dictWords =
          !_dictReady || normalizedQuery.length < 2
          ? <DictWord>[]
          : await _dictSearch.search(query: normalizedQuery);

      if (!mounted || token != _searchToken) return;

      final List<dynamic> combined = <dynamic>[];
      combined.addAll(customWords);
      combined.addAll(dictWords);

      setState(() {
        _results = combined;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = <dynamic>[];
      });
    } finally {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFD6DBE2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Color(0xFF8E98A7), size: 22),
                hintText: 'Search words',
                hintStyle: TextStyle(
                  color: Color(0xFF8E98A7),
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: !_dictReady && _initStatus.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(
                          _initStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF5A6775),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'Type to search words'
                            : 'No words found',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF5A6775),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                      itemCount: _results.length,
                      itemBuilder: (BuildContext context, int index) {
                        final dynamic item = _results[index];

                        String word = '';
                        String ipa = '';
                        String posAndMeaning = '';

                        if (item is Word) {
                          word = item.word;
                          posAndMeaning = item.meaning.isEmpty
                              ? '(${item.partOfSpeech})'
                              : '(${item.partOfSpeech}) ${item.meaning}';
                        } else if (item is DictWord) {
                          word = item.word;
                          ipa = item.ipa;
                          final String firstMeaning =
                              item.meaning.split('\n').first;
                          posAndMeaning = firstMeaning;
                        }

                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => WordDetailScreen(item: item),
                              ),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0066CC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        word,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (ipa.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            ipa,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFB3D9FF),
                                            ),
                                          ),
                                        ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(
                                          posAndMeaning,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFE8F0FF),
                                            height: 1.4,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
