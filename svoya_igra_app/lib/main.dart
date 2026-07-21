import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() => runApp(const SvoyaIgraApp());

class SvoyaIgraApp extends StatelessWidget {
  const SvoyaIgraApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Svoya Igra',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}
