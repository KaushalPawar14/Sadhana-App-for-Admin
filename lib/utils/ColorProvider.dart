import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColorProvider with ChangeNotifier {
  Color _color = Colors.white;  // Main color (default white)
  Color _secondColor = Colors.black;  // Second color (default black)
  Color _thirdColor = Colors.blue;
  Color _fourthColor = Colors.white70;

  Color get color => _color;
  Color get secondColor => _secondColor;
  Color get thirdColor => _thirdColor;
  Color get fourthColor => _fourthColor;

  // Constructor to load saved color preferences when the app starts
  ColorProvider() {
    _loadColorPreferences();
  }

  // Load color preferences from shared preferences
  Future<void> _loadColorPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isDarkMode = prefs.getBool('isDarkMode');

    if (isDarkMode == null || !isDarkMode) {
      // If no preference is saved, or it's false, set default light mode
      _color = Colors.white;
      _secondColor = Colors.black;
      _thirdColor = Colors.blueAccent;
      _fourthColor = Colors.white70;
    } else {
      // If dark mode is saved, set to dark mode
      _color = Colors.black87;
      _secondColor = Colors.white;
      _thirdColor = Colors.blueAccent;
      _fourthColor = Colors.grey[850]!;
    }
    notifyListeners();
  }

  // Toggle between white/black87 for the main color and between black/white for the second color
  Future<void> toggleColor() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (_color == Colors.white) {
      _color = Colors.black87;  // Change main color to black87
      _secondColor = Colors.white;  // Change second color to white
      _thirdColor = Colors.blueAccent;
      _fourthColor = Colors.grey[850]!;

      // Save the dark mode preference to SharedPreferences
      prefs.setBool('isDarkMode', true);
    } else {
      _color = Colors.white;  // Change main color to white
      _secondColor = Colors.black;  // Change second color to black
      _thirdColor = Colors.blueAccent;
      _fourthColor = Colors.white70;

      // Save the light mode preference to SharedPreferences
      prefs.setBool('isDarkMode', false);
    }
    notifyListeners();  // Notify listeners to rebuild UI
  }
}
