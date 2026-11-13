import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'board_reading.dart';
import 'geometry.dart';
import 'page_range.dart';
import 'reading_order.dart';
import 'recognition_service.dart';
import 'scan_engine.dart';

int _pageKeys = 0;

/// A new key that names a page in the recognition service.
int nextPageKey() => ++_pageKeys;

/// One scanned page (or the single image).
class ScanPage {
  ScanPage({
    required this.key,
    required this.jpeg,
    required this.width,
    required this.height,
    this.pageNumber,
    this.label = '',
  });

  final int key;

  /// The page as the recognition worker normalised it.
  final Uint8List jpeg;
  final int width;
  final int height;

  /// PDF page number (1-based), or `null` for a photo.
  final int? pageNumber;

  /// Short name for the page card, for example "Page 42".
  final String label;
}

/// One diagram on a page, ready for Review or saving.
class ScanBoard {
  ScanBoard({required this.id, required this.page, required RawBoard raw}) {
    apply(raw);
  }

  final int id;
  final ScanPage page;

  late Quad quad;
  late Uint8List cropPng;
  late BoardReading reading;

  bool selected = true;

  /// Position in the whole selection list, from 1.
  int number = 0;

  /// Reading-order position on its page, from 1.
  int indexOnPage = 0;

  void apply(RawBoard raw) {
    quad = raw.quad;
    cropPng = raw.cropPng;
    reading = interpretBoard(raw.probs);
  }
}

/// The boards found so far, over one or many pages, and which of them the
/// user wants to load.
class ScanSession extends ChangeNotifier {
  ScanSession(this.service);

  final RecognitionService service;

  final List<ScanPage> pages = [];
  List<ScanBoard> _boards = [];
  int _nextId = 1;
  bool _disposed = false;

  /// A short message while the models are working, otherwise `null`.
  String? get busy => _busy;
  String? _busy;

  /// All boards: pages in order, reading order inside a page.
  List<ScanBoard> get boards => List.unmodifiable(_boards);

  List<ScanBoard> get selected => [
        for (final b in _boards)
          if (b.selected) b,
      ];

  List<ScanBoard> boardsOn(ScanPage page) => [
        for (final b in _boards)
          if (b.page == page) b,
      ];

  /// Adds a page with the boards the models found on it.
  void addPage(ScanPage page, List<RawBoard> raws) {
    pages.add(page);
    for (final raw in raws) {
      _boards.add(ScanBoard(id: _nextId++, page: page, raw: raw));
    }
    _renumber();
    notifyListeners();
  }

  void _renumber() {
    final ordered = <ScanBoard>[];
    for (final page in pages) {
      final onPage = [
        for (final b in _boards)
          if (b.page == page) b,
      ];
      final order = readingOrder([for (final b in onPage) b.quad]);
      for (var i = 0; i < order.length; i++) {
        final b = onPage[order[i]];
        b.indexOnPage = i + 1;
        ordered.add(b);
      }
    }
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].number = i + 1;
    }
    _boards = ordered;
  }

  void toggle(ScanBoard board) {
    board.selected = !board.selected;
    notifyListeners();
  }

  void selectAll() => _setAll(true);

  void selectNone() => _setAll(false);

  void _setAll(bool value) {
    for (final b in _boards) {
      b.selected = value;
    }
    notifyListeners();
  }

  /// Selects exactly the boards whose numbers are in [numbers].
  void selectNumbers(Set<int> numbers) {
    for (final b in _boards) {
      b.selected = numbers.contains(b.number);
    }
    notifyListeners();
  }

  /// Parses a range such as `3-7, 9` and selects it. Returns an error message
  /// for the user, or `null` when it worked.
  String? selectRange(String text) {
    final parse = parseRange(text, _boards.length);
    final numbers = parse.numbers;
    if (numbers == null) return parse.error;
    selectNumbers(numbers);
    return null;
  }

  /// Re-reads [board] after the user moved its corners.
  Future<void> adjustCorners(ScanBoard board, Quad quad) async {
    _setBusy('Reading the board...');
    try {
      final raw = await service.readQuad(board.page.key, board.page.jpeg, quad);
      if (_disposed) return;
      board.apply(raw);
    } finally {
      _setBusy(null);
    }
  }

  /// Finds and reads a board inside [region], which the user drew on [page].
  Future<ScanBoard?> addBoardIn(ScanPage page, Quad region) async {
    _setBusy('Reading the board...');
    try {
      final raw = await service.readRegion(page.key, page.jpeg, region);
      if (_disposed) return null;
      final board = ScanBoard(id: _nextId++, page: page, raw: raw);
      _boards.add(board);
      _renumber();
      return board;
    } finally {
      _setBusy(null);
    }
  }

  void _setBusy(String? message) {
    if (_disposed) return;
    _busy = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
