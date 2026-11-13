import 'package:dartchess/dartchess.dart' show Side;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'collection_repository.dart';
import 'models.dart';

/// Version of the database schema. Add a step to [_migrations] and raise this
/// number to change the schema.
const int databaseSchemaVersion = 1;

/// File name of the database, in the app's databases folder.
const String databaseFileName = 'chesslens.db';

/// Schema changes by target version. `_migrations[2]` upgrades 1 to 2.
final Map<int, List<String>> _migrations = {
  // Example for the future: 2: ['ALTER TABLE puzzles ADD COLUMN something TEXT'],
};

const String _puzzleOrder =
    'COALESCE(page_number, 0), COALESCE(index_on_page, 0), id';

/// [CollectionRepository] on SQLite through sqflite.
class SqfliteCollectionRepository implements CollectionRepository {
  /// Opens `chesslens.db` in the default databases folder. Pass [factory] and
  /// [path] to use another SQLite implementation or location (tests).
  SqfliteCollectionRepository({DatabaseFactory? factory, String? path})
      : _factory = factory ?? databaseFactory,
        _path = path;

  final DatabaseFactory _factory;
  final String? _path;
  Future<Database>? _opening;

  Future<Database> get _db => _opening ??= _open();

  Future<Database> _open() async {
    final path = _path ?? p.join(await _factory.getDatabasesPath(), databaseFileName);
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseSchemaVersion,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''');
          await db.execute('''
CREATE TABLE puzzles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  fen TEXT NOT NULL,
  orientation TEXT NOT NULL,
  page_image_path TEXT,
  crop_image_path TEXT,
  page_number INTEGER,
  index_on_page INTEGER,
  status TEXT NOT NULL DEFAULT 'unsolved',
  attempts INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_at INTEGER NOT NULL
)''');
          await db.execute(
            'CREATE INDEX puzzles_collection ON puzzles(collection_id)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (var version = oldVersion + 1; version <= newVersion; version++) {
            for (final statement in _migrations[version] ?? const <String>[]) {
              await db.execute(statement);
            }
          }
        },
      ),
    );
  }

  // ------------------------------------------------------------ mapping

  static int _millis(DateTime time) => time.millisecondsSinceEpoch;
  static DateTime _time(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(value! as int);

  static Collection _collectionFromRow(Map<String, Object?> row) => Collection(
        id: row['id']! as int,
        name: row['name']! as String,
        createdAt: _time(row['created_at']),
        updatedAt: _time(row['updated_at']),
      );

  static Puzzle _puzzleFromRow(Map<String, Object?> row) => Puzzle(
        id: row['id']! as int,
        collectionId: row['collection_id']! as int,
        fen: row['fen']! as String,
        orientation: row['orientation'] == 'black' ? Side.black : Side.white,
        pageImagePath: row['page_image_path'] as String?,
        cropImagePath: row['crop_image_path'] as String?,
        pageNumber: row['page_number'] as int?,
        indexOnPage: row['index_on_page'] as int?,
        status: PuzzleStatus.values.firstWhere(
          (status) => status.name == row['status'],
          orElse: () => PuzzleStatus.unsolved,
        ),
        attempts: row['attempts']! as int,
        notes: row['notes'] as String?,
        createdAt: _time(row['created_at']),
      );

  static Map<String, Object?> _puzzleToRow(Puzzle puzzle) => {
        'collection_id': puzzle.collectionId,
        'fen': puzzle.fen,
        'orientation': puzzle.orientation.name,
        'page_image_path': puzzle.pageImagePath,
        'crop_image_path': puzzle.cropImagePath,
        'page_number': puzzle.pageNumber,
        'index_on_page': puzzle.indexOnPage,
        'status': puzzle.status.name,
        'attempts': puzzle.attempts,
        'notes': puzzle.notes,
        'created_at': _millis(puzzle.createdAt),
      };

  // ---------------------------------------------------------------- API

  @override
  Future<List<CollectionSummary>> listCollections() async {
    final db = await _db;
    final rows = await db.rawQuery('''
SELECT c.id, c.name, c.created_at, c.updated_at,
  (SELECT COUNT(*) FROM puzzles q WHERE q.collection_id = c.id) AS puzzle_count,
  (SELECT COUNT(*) FROM puzzles q
     WHERE q.collection_id = c.id AND q.status = 'solved') AS solved_count,
  (SELECT q.fen FROM puzzles q WHERE q.collection_id = c.id
     ORDER BY COALESCE(q.page_number, 0), COALESCE(q.index_on_page, 0), q.id
     LIMIT 1) AS preview_fen
FROM collections c
ORDER BY c.created_at DESC, c.id DESC''');
    return [
      for (final row in rows)
        CollectionSummary(
          collection: _collectionFromRow(row),
          puzzleCount: row['puzzle_count']! as int,
          solvedCount: row['solved_count']! as int,
          previewFen: row['preview_fen'] as String?,
        ),
    ];
  }

  @override
  Future<Collection> createCollection(String name) async {
    final db = await _db;
    final now = DateTime.now();
    final id = await db.insert('collections', {
      'name': name.trim(),
      'created_at': _millis(now),
      'updated_at': _millis(now),
    });
    return Collection(id: id, name: name.trim(), createdAt: now, updatedAt: now);
  }

  @override
  Future<void> renameCollection(int id, String name) async {
    final db = await _db;
    await db.update(
      'collections',
      {'name': name.trim(), 'updated_at': _millis(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteCollection(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('puzzles', where: 'collection_id = ?', whereArgs: [id]);
      await txn.delete('collections', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<Puzzle>> puzzlesIn(int collectionId) async {
    final db = await _db;
    final rows = await db.query(
      'puzzles',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      orderBy: _puzzleOrder,
    );
    return rows.map(_puzzleFromRow).toList();
  }

  @override
  Future<Puzzle?> getPuzzle(int id) async {
    final db = await _db;
    final rows = await db.query('puzzles', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _puzzleFromRow(rows.first);
  }

  @override
  Future<Puzzle> addPuzzle(Puzzle puzzle) async {
    final db = await _db;
    final id = await db.transaction((txn) async {
      final newId = await txn.insert('puzzles', _puzzleToRow(puzzle));
      await txn.update(
        'collections',
        {'updated_at': _millis(DateTime.now())},
        where: 'id = ?',
        whereArgs: [puzzle.collectionId],
      );
      return newId;
    });
    return puzzle.copyWith(id: id);
  }

  @override
  Future<void> updatePuzzle(Puzzle puzzle) async {
    final db = await _db;
    await db.update(
      'puzzles',
      _puzzleToRow(puzzle),
      where: 'id = ?',
      whereArgs: [puzzle.id],
    );
  }

  @override
  Future<void> deletePuzzle(int id) async {
    final db = await _db;
    await db.delete('puzzles', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> recordAttempt(int puzzleId, {required PuzzleStatus status}) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE puzzles SET status = ?, attempts = attempts + 1 WHERE id = ?',
      [status.name, puzzleId],
    );
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
