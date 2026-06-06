import 'dart:io';
import 'package:id3_codec/id3_codec.dart';
import '../models/track_model.dart';
import 'storage_service.dart';

class MetadataService {
  static Future<void> scanMusic() async {
    final home = Platform.environment['HOME'] ?? '';
    final dir = Directory('$home/Music');
    if (!await dir.exists()) return;

    final files = dir.listSync().where((f) => f.path.endsWith('.mp3'));
    
    for (var f in files) {
      final bytes = await File(f.path).readAsBytes();
      final tag = await ID3Decoder(bytes).decodeAsync();
      
      String title = 'Unknown Title';
      String artist = 'Unknown Artist';
      
      if (tag != null) {
        for (var frame in tag) {
          if (frame.toString().contains('TIT2')) title = frame.toString().split(':').last.trim();
          if (frame.toString().contains('TPE1')) artist = frame.toString().split(':').last.trim();
        }
      }

      final track = Track(path: f.path, title: title, artist: artist);
      await StorageService.box.put(f.path, track.toMap());
    }
  }
}