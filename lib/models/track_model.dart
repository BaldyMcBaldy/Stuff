class Track {
  final String path;
  final String title;
  final String artist;

  Track({required this.path, required this.title, required this.artist});

  Map<String, dynamic> toMap() => {'path': path, 'title': title, 'artist': artist};
  
  factory Track.fromMap(Map map) => Track(
    path: map['path'], 
    title: map['title'], 
    artist: map['artist']
  );
}