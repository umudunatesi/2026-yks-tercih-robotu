import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:yks_tercih_robotu/main.dart';

void main() {
  testWidgets('giriş ekranını gösterir', (tester) async {
    await tester
        .pumpWidget(const ProviderScope(child: MaterialApp(home: LoginPage())));
    await tester.pump();
    expect(find.text('Güvenli giriş'), findsOneWidget);
  });

  testWidgets('tercih geçmişi olan öğrencileri hatasız listeler',
      (tester) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: [
            {
              'id': 1,
              'first_name': 'Ayşe',
              'last_name': 'Yılmaz',
              'school': 'Örnek Lisesi',
              'graduation_status': 'Mezun',
              'phone': null,
              'email': null,
              'consent_given': true,
              'preference_count': 2,
              'preference_history': [
                {
                  'id': 2,
                  'name': 'İkinci Tercih',
                  'version': 1,
                  'status': 'draft',
                  'created_at': '2026-07-27T10:30:00'
                },
                {
                  'id': 1,
                  'name': 'İlk Tercih',
                  'version': 1,
                  'status': 'completed',
                  'created_at': '2026-07-26T09:15:00'
                }
              ]
            }
          ]));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const MaterialApp(home: StudentsPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(find.textContaining('Tercih çalışması: 2'), findsOneWidget);
    expect(find.textContaining('27.07.2026 10:30'), findsOneWidget);
  });
}
