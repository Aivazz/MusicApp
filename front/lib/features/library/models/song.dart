class Song {
  final String id;
  String videoId;
  final String title;
  final String artist;
  final String coverUrl;
  final Duration duration;
  final String type; // 'song', 'artist', 'Album', 'Playlist'
  final int? playCount;
  final int? followersCount;
  final String? yearText;

  Song({
    required this.id,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.coverUrl,
    this.duration = const Duration(minutes: 3, seconds: 30),
    this.type = 'song', // По умолчанию это песня
    this.playCount,
    this.followersCount,
    this.yearText,
  });

  Map<String, dynamic> toJson() {
    String savedVideoId = videoId;
    if (savedVideoId.startsWith('http://') || savedVideoId.startsWith('https://')) {
      savedVideoId = 'pirate:search:$artist - $title';
    }
    return {
      'id': id,
      'videoId': savedVideoId,
      'title': title,
      'artist': artist,
      'coverUrl': coverUrl,
      'duration': duration.inSeconds,
      'type': type,
      if (playCount != null) 'playCount': playCount,
      if (followersCount != null) 'followersCount': followersCount,
      if (yearText != null) 'yearText': yearText,
    };
  }

  factory Song.fromJson(Map<String, dynamic> j) {
    final id = j['id'] ?? j['videoId'] ?? '';
    var videoId = j['videoId'] ?? j['id'] ?? '';
    final title = j['title'] ?? '';
    final artist = j['artist'] ?? '';

    if (videoId.startsWith('http://') || videoId.startsWith('https://')) {
      videoId = 'pirate:search:$artist - $title';
    }

    return Song(
      id: id,
      videoId: videoId,
      title: title,
      artist: artist,
      coverUrl: j['coverUrl'] ?? '',
      duration: Duration(seconds: j['duration'] ?? 0),
      type: j['type'] ?? 'song',
      playCount: j['playCount'],
      followersCount: j['followersCount'],
      yearText: j['yearText'],
    );
  }
}

final List<Song> mockSongs = [];

final List<Map<String, String>> featuredArtists = [
  {
    'name': 'The Weeknd',
    'imageUrl':
        'https://i.scdn.co/image/ab6761610000e5eb214f3cf1cbe7139c1e26ffbb',
    'query': 'The Weeknd',
  },
  {
    'name': 'Taylor Swift',
    'imageUrl':
        'https://i.scdn.co/image/ab6761610000e5eb5a00969a4898c152a514d026',
    'query': 'Taylor Swift',
  },
  {
    'name': 'Maroon 5',
    'imageUrl':
        'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?q=80&w=400&fit=crop',
    'query': 'Maroon 5',
  },
];

final List<Map<String, String>> featuredMixes = [
  {
    'title': 'Top Hits 2024',
    'query': 'top hits english',
    'coverUrl':
        'https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400&auto=format&fit=crop',
  },
];

// 🌟 ДОБАВЛЕННЫЙ КЛАСС ИСТОРИИ ПОИСКА 🌟
class SearchHistoryEntry {
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final String type;

  SearchHistoryEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.type,
  });

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SearchHistoryEntry(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      coverUrl: json['coverUrl'] ?? '',
      type: json['type'] ?? 'song',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'coverUrl': coverUrl,
      'type': type,
    };
  }
}

class PlayHistoryEntry {
  final Song song;
  final DateTime playedAt;

  PlayHistoryEntry({
    required this.song,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'playedAt': playedAt.toIso8601String(),
  };

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) => PlayHistoryEntry(
    song: Song.fromJson(json['song']),
    playedAt: DateTime.parse(json['playedAt'] ?? DateTime.now().toIso8601String()),
  );
}

class RecentPlaylistEntry {
  final Song playlistMetadata;
  final String playlistType; // "Playlist", "Album", or "CustomPlaylist"
  final DateTime viewedAt;

  RecentPlaylistEntry({
    required this.playlistMetadata,
    required this.playlistType,
    required this.viewedAt,
  });

  Map<String, dynamic> toJson() => {
    'playlistMetadata': playlistMetadata.toJson(),
    'playlistType': playlistType,
    'viewedAt': viewedAt.toIso8601String(),
  };

  factory RecentPlaylistEntry.fromJson(Map<String, dynamic> json) => RecentPlaylistEntry(
    playlistMetadata: Song.fromJson(json['playlistMetadata']),
    playlistType: json['playlistType'] ?? 'Playlist',
    viewedAt: DateTime.parse(json['viewedAt'] ?? DateTime.now().toIso8601String()),
  );
}
