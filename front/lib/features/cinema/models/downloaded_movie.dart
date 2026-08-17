class DownloadedMovie {
  final String id;
  final String title;
  final String type;
  final String coverUrl;
  final String genre;
  final String year;
  final String localFilePath;

  DownloadedMovie({
    required this.id,
    required this.title,
    required this.type,
    required this.coverUrl,
    required this.genre,
    required this.year,
    required this.localFilePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'coverUrl': coverUrl,
        'genre': genre,
        'year': year,
        'localFilePath': localFilePath,
      };

  factory DownloadedMovie.fromJson(Map<String, dynamic> json) => DownloadedMovie(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        type: json['type'] ?? '',
        coverUrl: json['coverUrl'] ?? '',
        genre: json['genre'] ?? '',
        year: json['year'] ?? '',
        localFilePath: json['localFilePath'] ?? '',
      );
}
