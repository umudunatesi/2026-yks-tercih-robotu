import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yks_tercih_robotu/main.dart';

void main() {
  testWidgets('giriş ekranını gösterir', (tester) async {
    await tester
        .pumpWidget(const ProviderScope(child: MaterialApp(home: LoginPage())));
    await tester.pump();
    expect(find.text('Güvenli giriş'), findsOneWidget);
  });

  testWidgets('giriş ekranı telefon boyutunda taşmaz', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(const ProviderScope(child: MaterialApp(home: LoginPage())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Giriş yap'), findsOneWidget);
  });

  testWidgets('tercih geçmişi olan öğrencileri hatasız listeler',
      (tester) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: [
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
  testWidgets('rehber ogretmen girisi masaustunda ana sayfayi acar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/api/auth/login') {
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'access_token': 'test-token',
          'token_type': 'bearer',
          'user': {
            'id': 2,
            'email': 'rehber@example.com',
            'full_name': 'Rehber Ogretmen',
            'role': 'counselor'
          }
        }));
        return;
      }
      if (options.path == '/api/dashboard') {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'programs': 10, 'students': 0, 'preference_lists': 0}));
        return;
      }
      if (options.path == '/api/update/check') {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'configured': false,
              'available': false,
              'automatic_check': true
            }));
        return;
      }
      handler.reject(DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404)));
    }));

    await tester.pumpWidget(ProviderScope(overrides: [
      dioProvider.overrideWithValue(dio),
      initialTokenProvider.overrideWithValue(null),
      initialUserRoleProvider.overrideWithValue(null),
    ], child: const YksApp()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'rehber@example.com');
    await tester.enterText(fields.at(1), 'test-password');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
