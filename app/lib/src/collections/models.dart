import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/foundation.dart';

enum PuzzleStatus { unsolved, solved, failed }

@immutable
class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Collection copyWith({String? name, DateTime? updatedAt}) => Collection(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Collection &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
}

/// A collection with the numbers shown in the list.
@immutable
class CollectionSummary {
  const CollectionSummary({
    required this.collection,
    required this.puzzleCount,
    required this.solvedCount,
    this.previewFen,
  });

  final Collection collection;
  final int puzzleCount;
  final int solvedCount;

  /// FEN of the first puzzle, for a small preview.
  final String? previewFen;
}

@immutable
class Puzzle {
  const Puzzle({
    required this.id,
    required this.collectionId,
    required this.fen,
    required this.orientation,
    required this.createdAt,
    this.pageImagePath,
    this.cropImagePath,
    this.pageNumber,
    this.indexOnPage,
    this.status = PuzzleStatus.unsolved,
    this.attempts = 0,
    this.notes,
  });

  /// Id 0 means "not saved yet"; the repository assigns the real id.
  final int id;
  final int collectionId;

  /// Full FEN: placement, side to move, castling, en passant, clocks.
  final String fen;
  final Side orientation;
  final String? pageImagePath;
  final String? cropImagePath;
  final int? pageNumber;
  final int? indexOnPage;
  final PuzzleStatus status;
  final int attempts;
  final String? notes;
  final DateTime createdAt;

  Puzzle copyWith({
    int? id,
    int? collectionId,
    String? fen,
    Side? orientation,
    PuzzleStatus? status,
    int? attempts,
    String? notes,
  }) =>
      Puzzle(
        id: id ?? this.id,
        collectionId: collectionId ?? this.collectionId,
        fen: fen ?? this.fen,
        orientation: orientation ?? this.orientation,
        pageImagePath: pageImagePath,
        cropImagePath: cropImagePath,
        pageNumber: pageNumber,
        indexOnPage: indexOnPage,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        notes: notes ?? this.notes,
        createdAt: createdAt,
      );
}
