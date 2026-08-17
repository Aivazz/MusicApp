class MovieItem {
  final String id;
  final String title;
  final String type; // 'Фильм', 'Сериал', 'Аниме', 'Дорама'
  final String coverUrl;
  final String bannerUrl;
  final String rating;
  final String year;
  final String genre;
  final String description;
  final String country;

  MovieItem({
    required this.id,
    required this.title,
    required this.type,
    required this.coverUrl,
    required this.bannerUrl,
    required this.rating,
    required this.year,
    required this.genre,
    required this.description,
    this.country = 'Зарубежный',
  });
}
