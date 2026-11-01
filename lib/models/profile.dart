import 'models.dart';

/// Profil d'utilisateur (favoris, historique et reprise separes).
class Profile {
  final String id;
  final String name;
  final int color;

  /// Profil enfant : les categories verrouillees sont completement cachees.
  final bool kids;

  const Profile({
    required this.id,
    required this.name,
    this.color = 0,
    this.kids = false,
  });

  static const mainId = 'main';

  Profile copyWith({String? name, int? color, bool? kids}) => Profile(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        kids: kids ?? this.kids,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': color, 'kids': kids};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        color: (j['color'] as int?) ?? 0,
        kids: (j['kids'] as bool?) ?? false,
      );
}

/// Position de lecture sauvegardee d'un film ou d'un episode.
class WatchProgress {
  final Channel item;
  final int posMs;
  final int durMs;
  final int updatedMs;

  const WatchProgress(this.item, this.posMs, this.durMs, this.updatedMs);

  double get fraction => durMs <= 0 ? 0 : (posMs / durMs).clamp(0.0, 1.0);

  /// Vrai si la reprise a du sens (ni au tout debut, ni a la fin).
  bool get resumable => posMs > 30000 && (durMs <= 0 || fraction < 0.95);

  Map<String, dynamic> toJson() =>
      {'c': item.toJson(), 'p': posMs, 'd': durMs, 't': updatedMs};

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        Channel.fromJson(j['c'] as Map<String, dynamic>),
        j['p'] as int,
        j['d'] as int,
        j['t'] as int,
      );
}
