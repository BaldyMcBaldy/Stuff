import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:typed_data';

class ThemeService {
  // This function extracts colors from the bytes of your album art
  static Future<Map<String, Color>> generateColorsFromImage(Uint8List imageBytes) async {
    final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
      MemoryImage(imageBytes),
    );
    
    // Pick the dominant color, fallback to Gold if none found
    final Color primary = palette.dominantColor?.color ?? const Color(0xFFD4AF37);
    final Color container = primary.withOpacity(0.15);
    
    return {'primary': primary, 'container': container};
  }
}