import 'canvas_models.dart' show parseCanvasTimestamp;

/// One entry of the unified `GET /artifacts` list: a document, canvas, image,
/// PDF or file, with the same card shape for a list row or a chat link.
class ArtifactCard {
  const ArtifactCard({
    required this.id,
    required this.kind,
    this.subkind = '',
    this.title = '',
    this.session,
    this.updatedAt,
    this.rev = 0,
    this.author,
    this.thumbUrl,
  });

  /// Link target: a canvas id, or `<session>/<artifact id>` for documents.
  final String id;
  final String kind;
  final String subkind;
  final String title;
  final String? session;
  final DateTime? updatedAt;
  final int rev;
  final String? author;
  final String? thumbUrl;

  bool get isCanvas => kind == 'canvas';

  String get kindLabel => artifactKindLabel(kind);

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : id;

  /// Session and artifact id of a document card; null for canvases.
  ({String session, String id})? get documentRef {
    if (isCanvas) return null;
    final cut = id.lastIndexOf('/');
    if (cut <= 0 || cut == id.length - 1) return null;
    return (session: id.substring(0, cut), id: id.substring(cut + 1));
  }

  factory ArtifactCard.fromJson(Map<String, dynamic> j) {
    String? str(Object? v) {
      final t = v?.toString() ?? '';
      return t.isEmpty ? null : t;
    }

    return ArtifactCard(
      id: j['id']?.toString() ?? '',
      kind: j['kind']?.toString() ?? 'file',
      subkind: j['subkind']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      session: str(j['session']),
      updatedAt: parseCanvasTimestamp(j['updated_at']),
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      author: str(j['author']),
      thumbUrl: str(j['thumb_url']),
    );
  }
}

String artifactKindLabel(String kind) => switch (kind) {
      'document' => 'Document',
      'canvas' => 'Canvas',
      'image' => 'Image',
      'pdf' => 'PDF',
      _ => 'File',
    };

/// Filters by [query] over title, id, kind label and author, and by [kind]
/// when set. Keeps the server's newest-first order.
List<ArtifactCard> filterArtifactCards(
  List<ArtifactCard> cards, {
  String query = '',
  String? kind,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final c in cards)
      if ((kind == null || c.kind == kind) &&
          (q.isEmpty ||
              c.displayTitle.toLowerCase().contains(q) ||
              c.id.toLowerCase().contains(q) ||
              c.kindLabel.toLowerCase().contains(q) ||
              (c.author ?? '').toLowerCase().contains(q)))
        c,
  ];
}
