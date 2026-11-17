import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_movil/main.dart';

void main() {
  testWidgets('La aplicación muestra el inicio de sesión', (tester) async {
    await tester.pumpWidget(const GestionComercialApp());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsWidgets);
  });
}