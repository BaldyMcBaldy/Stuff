import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:typed_data';

// This is our Event Bus / State Manager
class MusicWorkstationController extends ChangeNotifier {
  Color primaryColor = const Color(0xFFD4AF37);
  Color containerColor = const Color(0xFF252114);

  // Update theme based on Album Art
  Future<void> updateThemeFromImage(Uint8List imageBytes) async {
    final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
      MemoryImage(imageBytes),
    );
    
    primaryColor = palette.dominantColor?.color ?? const Color(0xFFD4AF37);
    containerColor = primaryColor.withOpacity(0.15);
    notifyListeners(); // Tells the UI to repaint with new colors
  }
}