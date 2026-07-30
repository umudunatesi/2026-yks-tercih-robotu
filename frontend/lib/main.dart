import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' as picker;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final dioProvider = Provider((_) => Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_URL',
        defaultValue: 'http://127.0.0.1:8000'),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30))));
final themeProvider = StateProvider((_) => ThemeMode.light);
final initialTokenProvider = Provider<String?>((_) => null);
final initialUserRoleProvider = Provider<String?>((_) => null);
final initialPreferenceBasketProvider =
    Provider<List<Map<String, dynamic>>>((_) => const []);
final initialPreferenceStudentProvider = Provider<int?>((_) => null);
final initialPreferenceListNameProvider =
    Provider<String>((_) => '2026 YKS Tercih Listesi');
final tokenProvider =
    StateProvider<String?>((ref) => ref.watch(initialTokenProvider));
final userRoleProvider =
    StateProvider<String?>((ref) => ref.watch(initialUserRoleProvider));
final preferenceBasketProvider = StateProvider<List<Map<String, dynamic>>>(
    (ref) => ref.watch(initialPreferenceBasketProvider));
final selectedPreferenceStudentProvider =
    StateProvider<int?>((ref) => ref.watch(initialPreferenceStudentProvider));
final preferenceListNameProvider = StateProvider<String>(
    (ref) => ref.watch(initialPreferenceListNameProvider));
final comparisonProvider = StateProvider<List<Map<String, dynamic>>>((_) => []);
final sessionExpiredNotifier = ValueNotifier<bool>(false);
bool updateCheckStarted = false;

String dioErrorMessage(DioException error, String fallback) {
  dynamic data = error.response?.data;
  if (data is Uint8List) {
    try {
      data = jsonDecode(utf8.decode(data));
    } catch (_) {
      return fallback;
    }
  } else if (data is List<int>) {
    try {
      data = jsonDecode(utf8.decode(data));
    } catch (_) {
      return fallback;
    }
  }
  if (data is Map && data['detail'] != null) {
    return data['detail'].toString();
  }
  return fallback;
}

List<DropdownMenuItem<String>> filterItems(List<String> values) => [
      const DropdownMenuItem<String>(value: null, child: Text('Tümü')),
      ...values.map((x) => DropdownMenuItem(value: x, child: Text(x)))
    ];

Future<void> checkForAppUpdate(
  BuildContext context,
  WidgetRef ref, {
  bool silent = true,
}) async {
  try {
    final response = await ref.read(dioProvider).get('/api/update/check');
    if (!context.mounted) return;
    final data = Map<String, dynamic>.from(response.data as Map);
    if (silent && data['automatic_check'] == false) return;
    if (data['configured'] != true) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Güncelleme sunucusu henüz ayarlanmamış. Sistem Ayarları bölümünden manifest adresini girin.')));
      }
      return;
    }
    if (data['available'] != true) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Uygulama güncel: ${data['current_version'] ?? '—'}')));
      }
      return;
    }
    final notes = data['release_notes'] is List
        ? (data['release_notes'] as List).join('\n• ')
        : '${data['release_notes'] ?? ''}';
    final canInstall = ref.read(userRoleProvider) == 'admin';
    final install = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.system_update_alt),
              title: Text('Yeni sürüm ${data['version']} hazır'),
              content: SizedBox(
                  width: 520,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        'Mevcut sürüm: ${data['current_version']}\nYeni sürüm: ${data['version']}'),
                    if (notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('• $notes'))
                    ],
                    const SizedBox(height: 12),
                    const Text(
                        'Kurulumdan önce veritabanı yedeklenecek ve paket SHA-256 ile doğrulanacaktır.')
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Daha sonra')),
                if (canInstall)
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text('Güncelle'))
              ]),
        ) ??
        false;
    if (!install || !context.mounted) return;
    final installResponse =
        await ref.read(dioProvider).post('/api/update/install');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('${installResponse.data['message']}')));
    }
  } on DioException catch (error) {
    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.response?.data['detail']?.toString() ??
              'Güncelleme kontrol edilemedi.')));
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  String? token = preferences.getString('access_token');
  String? userRole;
  final savedBasket = <Map<String, dynamic>>[];
  final basketJson = preferences.getString('preference_draft_basket');
  if (basketJson != null) {
    try {
      savedBasket.addAll((jsonDecode(basketJson) as List)
          .map((item) => Map<String, dynamic>.from(item as Map)));
    } catch (_) {
      await preferences.remove('preference_draft_basket');
    }
  }
  final savedStudentId = preferences.getInt('preference_draft_student_id');
  final savedListName = preferences.getString('preference_draft_list_name') ??
      '2026 YKS Tercih Listesi';
  final dio = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment('API_URL',
          defaultValue: 'http://127.0.0.1:8000'),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30)));
  dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) async {
    if (error.response?.statusCode == 401) {
      dio.options.headers.remove('Authorization');
      await preferences.remove('access_token');
      sessionExpiredNotifier.value = true;
    }
    handler.next(error);
  }));
  if (token != null) {
    dio.options.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await dio.get('/api/auth/me');
      userRole = response.data['role'] as String?;
    } on DioException {
      token = null;
      dio.options.headers.remove('Authorization');
      await preferences.remove('access_token');
    }
  }
  runApp(ProviderScope(overrides: [
    initialTokenProvider.overrideWithValue(token),
    initialUserRoleProvider.overrideWithValue(userRole),
    initialPreferenceBasketProvider.overrideWithValue(savedBasket),
    initialPreferenceStudentProvider.overrideWithValue(savedStudentId),
    initialPreferenceListNameProvider.overrideWithValue(savedListName),
    dioProvider.overrideWithValue(dio)
  ], child: const YksApp()));
}

class YksApp extends ConsumerWidget {
  const YksApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(preferenceBasketProvider, (_, next) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('preference_draft_basket', jsonEncode(next));
    });
    ref.listen(selectedPreferenceStudentProvider, (_, next) async {
      final preferences = await SharedPreferences.getInstance();
      if (next == null) {
        await preferences.remove('preference_draft_student_id');
      } else {
        await preferences.setInt('preference_draft_student_id', next);
      }
    });
    ref.listen(preferenceListNameProvider, (_, next) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('preference_draft_list_name', next);
    });
    final router = GoRouter(
        refreshListenable: sessionExpiredNotifier,
        redirect: (_, state) {
          if (sessionExpiredNotifier.value &&
              state.matchedLocation != '/giris') {
            return '/giris';
          }
          const authenticatedPaths = {
            '/',
            '/ogrenciler',
            '/tercih',
            '/raporlar',
          };
          const adminPaths = {
            '/veri-aktar',
            '/kullanicilar',
            '/denetim',
            '/ayarlar',
          };
          if ((authenticatedPaths.contains(state.matchedLocation) ||
                  adminPaths.contains(state.matchedLocation)) &&
              ref.read(tokenProvider) == null) {
            return '/giris';
          }
          if (adminPaths.contains(state.matchedLocation) &&
              ref.read(userRoleProvider) != 'admin') {
            return '/';
          }
          return null;
        },
        routes: [
          ShellRoute(
              builder: (_, state, child) => AppShell(child: child),
              routes: [
                GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
                GoRoute(
                    path: '/programlar',
                    builder: (_, __) => const ProgramsPage()),
                GoRoute(
                    path: '/ozel-yetenek',
                    builder: (_, __) => const SpecialTalentProgramsPage()),
                GoRoute(
                    path: '/ogrenciler',
                    builder: (_, __) => const StudentsPage()),
                GoRoute(
                    path: '/tercih',
                    builder: (_, __) => const PreferencePage()),
                GoRoute(
                    path: '/karsilastir',
                    builder: (_, __) => const ComparePage()),
                GoRoute(
                    path: '/raporlar', builder: (_, __) => const ReportsPage()),
                GoRoute(
                    path: '/veri-aktar',
                    builder: (_, __) => const ImportPage()),
                GoRoute(
                    path: '/kullanicilar',
                    builder: (_, __) => const UsersPage()),
                GoRoute(
                    path: '/denetim', builder: (_, __) => const AuditPage()),
                GoRoute(
                    path: '/ayarlar', builder: (_, __) => const SettingsPage()),
              ]),
          GoRoute(path: '/giris', builder: (_, __) => const LoginPage())
        ]);
    return MaterialApp.router(
        title: '2026 YKS Tercih Robotu',
        debugShowCheckedModeBanner: false,
        themeMode: ref.watch(themeProvider),
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff8174c9),
                primary: const Color(0xff7567b5),
                secondary: const Color(0xff55a99a),
                tertiary: const Color(0xffe79972),
                surface: const Color(0xfffffbff),
                brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xfff8f6fc),
            cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xfffffbff),
                surfaceTintColor: Colors.transparent,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shadowColor: const Color(0xff7768a8).withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xffebe5f4)))),
            navigationDrawerTheme: NavigationDrawerThemeData(
                backgroundColor: const Color(0xfff1edfa),
                indicatorColor: const Color(0xffddd6f7),
                indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0),
            appBarTheme: const AppBarTheme(
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: false,
                backgroundColor: Color(0xffeee9f8),
                foregroundColor: Color(0xff40385f),
                titleTextStyle: TextStyle(
                    color: Color(0xff40385f),
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            snackBarTheme: SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xff4e4964),
                contentTextStyle: const TextStyle(color: Colors.white),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xfffffbff),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xffded7e9))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xffded7e9))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                        color: Color(0xff8174c9), width: 1.6))),
            filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
            outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
            chipTheme: ChipThemeData(backgroundColor: const Color(0xffe5f4ef), selectedColor: const Color(0xffdcd5f5), side: BorderSide.none, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            dividerTheme: const DividerThemeData(color: Color(0xffded8e8), thickness: 1),
            useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xff7aa2ff), brightness: Brightness.dark, useMaterial3: true),
        routerConfig: router);
  }
}

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({required this.child, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tokenProvider) != null && !updateCheckStarted) {
      updateCheckStarted = true;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => checkForAppUpdate(context, ref, silent: true));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final permanentMenu = constraints.maxWidth >= 1100;
      return Scaffold(
          appBar: AppBar(
              leading: permanentMenu
                  ? Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset('assets/branding/app-icon.png'))
                  : Builder(
                      builder: (menuContext) => IconButton(
                          tooltip: 'Menüyü aç',
                          onPressed: () =>
                              Scaffold.of(menuContext).openDrawer(),
                          icon: const Icon(Icons.menu))),
              title: const Text('2026 YKS Tercih Robotu'),
              actions: [
                if (ref.watch(tokenProvider) != null)
                  IconButton(
                      tooltip: 'Güncellemeleri kontrol et',
                      onPressed: () =>
                          checkForAppUpdate(context, ref, silent: false),
                      icon: const Icon(Icons.system_update_alt)),
                IconButton(
                    tooltip: ref.watch(tokenProvider) == null
                        ? 'Giriş yap'
                        : 'Çıkış yap',
                    onPressed: () {
                      final dio = ref.read(dioProvider);
                      if (ref.read(tokenProvider) == null) {
                        context.go('/giris');
                      } else {
                        ref.read(tokenProvider.notifier).state = null;
                        ref.read(userRoleProvider.notifier).state = null;
                        dio.options.headers.remove('Authorization');
                        SharedPreferences.getInstance()
                            .then((value) => value.remove('access_token'));
                        sessionExpiredNotifier.value = true;
                        context.go('/giris');
                      }
                    },
                    icon: Icon(ref.watch(tokenProvider) == null
                        ? Icons.login
                        : Icons.logout)),
                IconButton(
                    tooltip: 'Tema',
                    onPressed: () {
                      final n = ref.read(themeProvider.notifier);
                      n.state = n.state == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                    },
                    icon: const Icon(Icons.contrast))
              ]),
          drawer: permanentMenu ? null : _navigation(context, ref, true),
          body: permanentMenu
              ? Row(children: [
                  SizedBox(width: 285, child: _navigation(context, ref, false)),
                  const VerticalDivider(width: 1),
                  Expanded(child: child)
                ])
              : child);
    });
  }

  Widget _navigation(BuildContext context, WidgetRef ref, bool closeDrawer) =>
      NavigationDrawer(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xfffff7ed),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xff8174c9).withValues(alpha: 0.13),
                            blurRadius: 18,
                            offset: const Offset(0, 6))
                      ]),
                  child: Image.asset('assets/branding/app-icon.png')),
              const SizedBox(height: 14),
              const Text('Karar Destek Sistemi',
                  style: TextStyle(
                      color: Color(0xff40385f),
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  ref.watch(tokenProvider) == null
                      ? 'Oturum açılmadı'
                      : 'Rol: ${roleLabel(ref.watch(userRoleProvider))}',
                  style: Theme.of(context).textTheme.bodySmall),
              Text('Sürüm 1.3.8',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text('Programı hazırlayan:\nPsikolojik Danışman Uğur Güdük',
                  style: Theme.of(context).textTheme.labelSmall)
            ])),
        _nav(
            context, Icons.dashboard_outlined, 'Genel Bakış', '/', closeDrawer),
        if (ref.watch(tokenProvider) != null)
          _nav(context, Icons.people_outline, 'Öğrenciler', '/ogrenciler',
              closeDrawer),
        _nav(context, Icons.search, 'Program Ara', '/programlar', closeDrawer),
        _nav(context, Icons.palette_outlined, 'Özel Yetenek Sınavı Programları',
            '/ozel-yetenek', closeDrawer),
        if (ref.watch(tokenProvider) != null) ...[
          _nav(context, Icons.format_list_numbered, 'Tercih Listesi', '/tercih',
              closeDrawer),
        ],
        _nav(context, Icons.compare_arrows, 'Karşılaştırma', '/karsilastir',
            closeDrawer),
        if (ref.watch(tokenProvider) != null)
          _nav(context, Icons.analytics_outlined, 'Raporlar', '/raporlar',
              closeDrawer),
        if (ref.watch(userRoleProvider) == 'admin') ...[
          _nav(context, Icons.upload_file, 'Excel Veri Aktarımı', '/veri-aktar',
              closeDrawer),
          _nav(context, Icons.manage_accounts, 'Kullanıcı Yönetimi',
              '/kullanicilar', closeDrawer),
          _nav(context, Icons.history_toggle_off, 'Denetim Kayıtları',
              '/denetim', closeDrawer),
          _nav(context, Icons.settings_outlined, 'Sistem Ayarları', '/ayarlar',
              closeDrawer),
        ],
      ]);

  String roleLabel(String? role) =>
      const {
        'admin': 'Yönetici',
        'counselor': 'Rehber öğretmen',
        'teacher': 'Öğretmen',
        'viewer': 'Görüntüleyici',
      }[role] ??
      'Bilinmiyor';

  Widget _nav(
      BuildContext c, IconData i, String t, String p, bool closeDrawer) {
    final currentPath = GoRouterState.of(c).uri.path;
    final selected = p == '/' ? currentPath == '/' : currentPath.startsWith(p);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: ListTile(
            selected: selected,
            selectedColor: const Color(0xff55488e),
            selectedTileColor: const Color(0xffddd6f7),
            iconColor: const Color(0xff6d6581),
            textColor: const Color(0xff514a60),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xfffff6e8)
                        : const Color(0xffe3f3ef),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(i, size: 21)),
            title: Text(t,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            onTap: () {
              if (closeDrawer) Navigator.pop(c);
              c.go(p);
            }));
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  String? error;

  Future<void> login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post('/api/auth/login',
          data: {
            'username': email.text.trim().toLowerCase(),
            'password': password.text
          },
          options: Options(contentType: Headers.formUrlEncodedContentType));
      final token = response.data['access_token'] as String;
      sessionExpiredNotifier.value = false;
      ref.read(tokenProvider.notifier).state = token;
      ref.read(userRoleProvider.notifier).state =
          response.data['user']['role'] as String?;
      dio.options.headers['Authorization'] = 'Bearer $token';
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('access_token', token);
      if (mounted) context.go('/');
    } on DioException catch (e) {
      setState(() => error = e.response?.data['detail'] ?? 'Giriş yapılamadı');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                                child: Image.asset(
                                    'assets/branding/app-icon.png',
                                    width: 76,
                                    height: 76)),
                            const SizedBox(height: 12),
                            Text('Güvenli giriş',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 20),
                            TextField(
                                controller: email,
                                autofocus: true,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                    labelText: 'E-posta',
                                    hintText: 'ornek@eposta.com',
                                    prefixIcon: Icon(Icons.email_outlined))),
                            const SizedBox(height: 12),
                            TextField(
                                controller: password,
                                obscureText: obscurePassword,
                                onSubmitted: (_) => login(),
                                decoration: InputDecoration(
                                    labelText: 'Şifre',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                        tooltip: obscurePassword
                                            ? 'Şifreyi göster'
                                            : 'Şifreyi gizle',
                                        onPressed: () => setState(() =>
                                            obscurePassword = !obscurePassword),
                                        icon: Icon(obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined)))),
                            if (error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                                onPressed: loading ? null : login,
                                icon: loading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.login),
                                label: const Text('Giriş yap'))
                          ]))))));
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
      future: ref.read(dioProvider).get('/api/dashboard'),
      builder: (_, s) {
        final d = (s.data?.data as Map?) ?? {};
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Hoş geldiniz',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
              'Öğrencileriniz için veriye dayalı, açıklanabilir tercih listeleri hazırlayın.'),
          const SizedBox(height: 24),
          Wrap(spacing: 16, runSpacing: 16, children: [
            StatCard(
                icon: Icons.school,
                label: 'Program',
                value: '${d['programs'] ?? '—'}',
                backgroundColor: const Color(0xffe7e0f8),
                accentColor: const Color(0xff6f5aa8)),
            StatCard(
                icon: Icons.people,
                label: 'Öğrenci',
                value: '${d['students'] ?? '—'}',
                backgroundColor: const Color(0xffdff3ed),
                accentColor: const Color(0xff3f8d7e)),
            StatCard(
                icon: Icons.list_alt,
                label: 'Tercih Listesi',
                value: '${d['preference_lists'] ?? '—'}',
                backgroundColor: const Color(0xffffeadc),
                accentColor: const Color(0xffb56e4e)),
          ]),
          const SizedBox(height: 24),
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Bu sistem yalnızca karar destek amacıyla hazırlanmıştır. Tercih sonuçlarına ilişkin kesin yerleşme garantisi vermez. Güncel ÖSYM/YÖK kılavuzu ve özel koşullar mutlaka kontrol edilmelidir.'))),
          const SizedBox(height: 12),
          const Align(
              alignment: Alignment.center,
              child: Text('Programı hazırlayan: Psikolojik Danışman Uğur Güdük',
                  style: TextStyle(fontWeight: FontWeight.w600)))
        ]);
      });
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color backgroundColor, accentColor;
  const StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      this.backgroundColor = const Color(0xffe7e0f8),
      this.accentColor = const Color(0xff6f5aa8),
      super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 240,
      child: Card(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: accentColor.withValues(alpha: 0.18))),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(17)),
                    child: Icon(icon, size: 29, color: accentColor)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(value,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w800)),
                      Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: accentColor.withValues(alpha: 0.86),
                              fontWeight: FontWeight.w600))
                    ]))
              ]))));
}

Color scoreTypeColor(String? scoreType) => switch (scoreType) {
      'SAY' => const Color(0xff62a9d1),
      'EA' => const Color(0xff9b7bc5),
      'SÖZ' => const Color(0xffe58a70),
      'DİL' => const Color(0xff58aa91),
      'TYT' => const Color(0xffd5a84f),
      _ => const Color(0xff8b8495),
    };

String kpssDisplay(dynamic extra) {
  if (extra is! Map || extra['kpss'] == null) return '—';
  final value = extra['kpss'];
  final number = value is num ? value : num.tryParse('$value');
  return number == null ? '$value' : NumberFormat('0.000', 'tr').format(number);
}

class SpecialTalentProgramsPage extends ConsumerStatefulWidget {
  const SpecialTalentProgramsPage({super.key});

  @override
  ConsumerState<SpecialTalentProgramsPage> createState() =>
      _SpecialTalentProgramsPageState();
}

class _SpecialTalentProgramsPageState
    extends ConsumerState<SpecialTalentProgramsPage> {
  final search = TextEditingController();
  final university = TextEditingController();
  final minQuota = TextEditingController();
  final maxQuota = TextEditingController();
  String? institutionType;
  String? accreditation;
  String? conditionCode;
  bool kktcNationalOnly = false;
  bool loading = false;
  String? error;
  String source = '';
  int total = 0;
  int page = 1;
  static const pageSize = 40;
  List<Map<String, dynamic>> items = [];
  List<String> accreditationOptions = [];
  List<String> conditionOptions = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    university.dispose();
    minQuota.dispose();
    maxQuota.dispose();
    super.dispose();
  }

  Future<void> load({bool resetPage = false}) async {
    if (resetPage) page = 1;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response =
          await ref.read(dioProvider).get('/api/special-talent-programs',
              queryParameters: {
                'q': search.text.trim().isEmpty ? null : search.text.trim(),
                'university': university.text.trim().isEmpty
                    ? null
                    : university.text.trim(),
                'institution_type': institutionType,
                'accreditation': accreditation,
                'condition_code': conditionCode,
                'min_quota': int.tryParse(minQuota.text),
                'max_quota': int.tryParse(maxQuota.text),
                'kktc_national_only': kktcNationalOnly ? true : null,
                'page': page,
                'page_size': pageSize,
              }..removeWhere((_, value) => value == null));
      final data = Map<String, dynamic>.from(response.data as Map);
      final filters =
          Map<String, dynamic>.from((data['filters'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        total = (data['total'] as num?)?.toInt() ?? 0;
        source = '${data['source'] ?? ''}';
        items = ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        accreditationOptions =
            ((filters['accreditations'] as List?) ?? const [])
                .map((item) => '$item')
                .toList();
        conditionOptions = ((filters['condition_codes'] as List?) ?? const [])
            .map((item) => '$item')
            .toList();
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = 'Özel yetenek programları yüklenemedi.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void clearFilters() {
    search.clear();
    university.clear();
    minQuota.clear();
    maxQuota.clear();
    setState(() {
      institutionType = null;
      accreditation = null;
      conditionCode = null;
      kktcNationalOnly = false;
    });
    load(resetPage: true);
  }

  Widget information(String label, dynamic value, {double width = 205}) =>
      Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xfff5f2fb),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xff655d73))),
            const SizedBox(height: 3),
            SelectableText(
                value == null || '$value'.trim().isEmpty ? '—' : '$value',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))
          ]));

  @override
  Widget build(BuildContext context) {
    final first = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final last = ((page - 1) * pageSize + items.length).clamp(0, total);
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Özel Yetenek Sınavı Programları',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(source,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xff655d73))),
          const SizedBox(height: 12),
          Card(
              color: const Color(0xfffff1dc),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.tune, color: Color(0xffa45e35)),
                          const SizedBox(width: 8),
                          Text('Filtreler',
                              style: Theme.of(context).textTheme.titleMedium)
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          SizedBox(
                              width: 270,
                              child: TextField(
                                  controller: search,
                                  onSubmitted: (_) => load(resetPage: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Program, kod veya fakülte',
                                      prefixIcon: Icon(Icons.search)))),
                          SizedBox(
                              width: 270,
                              child: TextField(
                                  controller: university,
                                  onSubmitted: (_) => load(resetPage: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Üniversite ara',
                                      prefixIcon:
                                          Icon(Icons.account_balance)))),
                          SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                  initialValue: institutionType,
                                  decoration: const InputDecoration(
                                      labelText: 'Kurum türü'),
                                  items: const ['Devlet', 'Vakıf', 'KKTC']
                                      .map((value) => DropdownMenuItem(
                                          value: value, child: Text(value)))
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => institutionType = value))),
                          SizedBox(
                              width: 180,
                              child: DropdownButtonFormField<String>(
                                  initialValue: accreditation,
                                  decoration: const InputDecoration(
                                      labelText: 'Akreditasyon'),
                                  items: accreditationOptions
                                      .map((value) => DropdownMenuItem(
                                          value: value, child: Text(value)))
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => accreditation = value))),
                          SizedBox(
                              width: 165,
                              child: DropdownButtonFormField<String>(
                                  initialValue: conditionCode,
                                  decoration: const InputDecoration(
                                      labelText: 'Özel koşul'),
                                  items: conditionOptions
                                      .map((value) => DropdownMenuItem(
                                          value: value,
                                          child: Text('Bk. $value')))
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => conditionCode = value))),
                          SizedBox(
                              width: 135,
                              child: TextField(
                                  controller: minQuota,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Min. kontenjan'))),
                          SizedBox(
                              width: 135,
                              child: TextField(
                                  controller: maxQuota,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Maks. kontenjan'))),
                          FilterChip(
                              selected: kktcNationalOnly,
                              avatar: const Icon(Icons.badge_outlined),
                              label: const Text('KKTC Uyruklu'),
                              onSelected: (value) =>
                                  setState(() => kktcNationalOnly = value)),
                          FilledButton.icon(
                              onPressed: () => load(resetPage: true),
                              icon: const Icon(Icons.filter_alt),
                              label: const Text('Uygula')),
                          TextButton(
                              onPressed: clearFilters,
                              child: const Text('Filtreleri temizle'))
                        ])
                      ]))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text('$total program bulundu',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            if (total > 0) Text('$first-$last arası gösteriliyor')
          ]),
          const SizedBox(height: 6),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cloud_off, size: 48),
                          const SizedBox(height: 8),
                          Text(error!),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                              onPressed: load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar dene'))
                        ]))
                      : items.isEmpty
                          ? const Center(
                              child: Text(
                                  'Filtrelere uygun özel yetenek programı bulunamadı.'))
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final program = items[index];
                                final codes =
                                    ((program['special_condition_codes']
                                                as List?) ??
                                            const [])
                                        .map((item) => '$item')
                                        .toList();
                                final details =
                                    ((program['special_condition_details']
                                                as List?) ??
                                            const [])
                                        .whereType<Map>()
                                        .map((item) =>
                                            Map<String, dynamic>.from(item))
                                        .toList();
                                return Card(
                                    child: ExpansionTile(
                                        leading: CircleAvatar(
                                            backgroundColor: switch (
                                                program['institution_type']) {
                                              'Devlet' =>
                                                const Color(0xff7ba8d1),
                                              'Vakıf' =>
                                                const Color(0xffb085c6),
                                              'KKTC' => const Color(0xff59aa91),
                                              _ => const Color(0xff8b8495),
                                            },
                                            foregroundColor: Colors.white,
                                            child: Text(
                                                '${program['quota'] ?? '—'}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w800))),
                                        title: Wrap(
                                            spacing: 7,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text('${program['program']}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              Chip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  label: Text(
                                                      '${program['institution_type']}')),
                                              if (program['fee_status'] != null)
                                                Chip(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text(
                                                        '${program['fee_status']}')),
                                              if (program[
                                                      'kktc_national_only'] ==
                                                  true)
                                                const Chip(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text('KKTC Uyruklu'))
                                            ]),
                                        subtitle: Text(
                                            '${program['university']}\n${program['unit']} • Kod: ${program['program_code']}'),
                                        childrenPadding:
                                            const EdgeInsets.fromLTRB(
                                                16, 0, 16, 16),
                                        children: [
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            information('Program kodu',
                                                program['program_code']),
                                            information('Üniversite',
                                                program['university'],
                                                width: 310),
                                            information(
                                                'Fakülte / YO', program['unit'],
                                                width: 280),
                                            information('Kurum türü',
                                                program['institution_type']),
                                            information(
                                                'Yer', program['location']),
                                            information(
                                                'Kontenjan', program['quota']),
                                            information(
                                                'Özel koşul kodları',
                                                codes.isEmpty
                                                    ? '—'
                                                    : codes
                                                        .map((code) =>
                                                            'Bk. $code')
                                                        .join(', ')),
                                            information(
                                                'Türkiye Yeterlilikler Çerçevesi',
                                                program['tyc']),
                                            information(
                                                'Program akreditasyonu',
                                                program[
                                                    'program_accreditation']),
                                            information(
                                                'Üniversite akreditasyonu',
                                                program[
                                                    'university_accreditation']),
                                            information('Ücret durumu',
                                                program['fee_status']),
                                            information('Kaynak sayfa',
                                                program['source_printed_page'])
                                          ]),
                                      if (details.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                                'Özel koşul ve açıklamalar',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium)),
                                        const SizedBox(height: 6),
                                        ...details.map((condition) => Card(
                                            color: const Color(0xfffff7e8),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: SelectableText(
                                                        'Bk. ${condition['code']}: ${condition['description']}')))))
                                      ]
                                    ]));
                              })),
          if (total > pageSize)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton.icon(
                      onPressed: loading || page <= 1
                          ? null
                          : () {
                              setState(() => page--);
                              load();
                            },
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Önceki')),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                          '$page / ${((total + pageSize - 1) / pageSize).floor()}')),
                  FilledButton.tonalIcon(
                      onPressed: loading || page * pageSize >= total
                          ? null
                          : () {
                              setState(() => page++);
                              load();
                            },
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Sonraki'))
                ]))
        ]));
  }
}

class ProgramsPage extends ConsumerStatefulWidget {
  const ProgramsPage({super.key});
  @override
  ConsumerState<ProgramsPage> createState() => _ProgramsPageState();
}

class _ProgramsPageState extends ConsumerState<ProgramsPage> {
  final search = TextEditingController();
  final university = TextEditingController();
  final city = TextEditingController();
  final minRank = TextEditingController();
  final maxRank = TextEditingController();
  final minQuota = TextEditingController();
  String? level;
  final Set<String> scoreTypes = {};
  final Set<String> statuses = {};
  final Set<String> universityTypes = {};
  final Set<String> feeStatuses = {};
  final Set<String> languages = {};
  final Set<String> educationTypes = {};
  final Set<String> regions = {};
  bool accreditedOnly = false;
  bool schoolTopOnly = false;
  bool martyrVeteranOnly = false;
  bool women34Only = false;
  List items = [];
  int total = 0;
  int page = 1;
  static const int pageSize = 50;
  bool loading = false;
  String? loadError;
  List<Map<String, dynamic>> favorites = [];
  final Set<int> selectedProgramIds = {};
  Timer? searchDebounce;
  int loadGeneration = 0;

  void scheduleSearch(String _) {
    searchDebounce?.cancel();
    searchDebounce =
        Timer(const Duration(milliseconds: 450), () => load(resetPage: true));
  }

  Future<void> load({bool resetPage = false}) async {
    if (!mounted) return;
    final requestGeneration = ++loadGeneration;
    setState(() {
      if (resetPage) page = 1;
      loading = true;
      loadError = null;
    });
    try {
      final queryParameters = <String, dynamic>{
        'q': search.text,
        'level': level,
        'city': city.text.isEmpty ? null : city.text,
        'university': university.text.isEmpty ? null : university.text,
        'regions': regions.isEmpty ? null : regions.join(','),
        'score_type': scoreTypes.isEmpty ? null : scoreTypes.join(','),
        'university_type':
            universityTypes.isEmpty ? null : universityTypes.join(','),
        'fee_status': feeStatuses.isEmpty ? null : feeStatuses.join(','),
        'language': languages.isEmpty ? null : languages.join(','),
        'education_type':
            educationTypes.isEmpty ? null : educationTypes.join(','),
        'status': statuses.isEmpty ? null : statuses.join(','),
        'accreditation': accreditedOnly ? true : null,
        'school_top_quota': schoolTopOnly ? true : null,
        'martyr_veteran_quota': martyrVeteranOnly ? true : null,
        'women_34_quota': women34Only ? true : null,
        'min_rank': int.tryParse(minRank.text),
        'max_rank': int.tryParse(maxRank.text),
        'min_quota': int.tryParse(minQuota.text),
        'page': page,
        'page_size': pageSize
      }..removeWhere(
          (_, value) => value == null || (value is String && value.isEmpty));
      final r = await ref
          .read(dioProvider)
          .get('/api/programs', queryParameters: queryParameters);
      if (!mounted || requestGeneration != loadGeneration) return;
      setState(() {
        items = r.data['items'];
        total = r.data['total'];
      });
    } on DioException catch (e) {
      if (!mounted || requestGeneration != loadGeneration) return;
      setState(() {
        loadError = e.response?.data is Map
            ? '${e.response?.data['detail'] ?? 'Programlar yüklenemedi.'}'
            : 'Programlar yüklenemedi. Sunucu bağlantısını kontrol edin.';
      });
    } finally {
      if (mounted && requestGeneration == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  void addProgram(Map program) {
    final current = ref.read(preferenceBasketProvider);
    if (current.any((x) => x['id'] == program['id'])) {
      return;
    }
    ref.read(preferenceBasketProvider.notifier).state = [
      ...current,
      Map<String, dynamic>.from(program)
    ];
  }

  void addSelectedPrograms() {
    final current = ref.read(preferenceBasketProvider);
    final currentIds = current.map((x) => x['id']).toSet();
    final additions = items
        .where((program) =>
            selectedProgramIds.contains(program['id']) &&
            !currentIds.contains(program['id']))
        .map<Map<String, dynamic>>(
            (program) => Map<String, dynamic>.from(program))
        .toList();
    ref.read(preferenceBasketProvider.notifier).state = [
      ...current,
      ...additions
    ];
    setState(() => selectedProgramIds.clear());
  }

  Future<void> loadFavorites() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('favorite_programs');
    if (raw == null || !mounted) return;
    try {
      final decoded = jsonDecode(raw) as List;
      setState(() {
        favorites =
            decoded.map((x) => Map<String, dynamic>.from(x as Map)).toList();
      });
    } catch (_) {
      await preferences.remove('favorite_programs');
    }
  }

  Future<void> toggleFavorite(Map program) async {
    final id = program['id'];
    setState(() {
      if (favorites.any((x) => x['id'] == id)) {
        favorites.removeWhere((x) => x['id'] == id);
      } else {
        favorites.add(Map<String, dynamic>.from(program));
      }
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('favorite_programs', jsonEncode(favorites));
  }

  Future<void> showFavorites() async {
    await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: Text('Favori programlar (${favorites.length})'),
                    content: SizedBox(
                        width: 760,
                        height: 520,
                        child: favorites.isEmpty
                            ? const Center(
                                child: Text(
                                    'Henüz favori program eklenmedi.\nProgramların yanındaki yıldız simgesini kullanın.',
                                    textAlign: TextAlign.center))
                            : ListView.separated(
                                itemCount: favorites.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, index) {
                                  final program = favorites[index];
                                  return ListTile(
                                      leading: const Icon(Icons.star,
                                          color: Colors.amber),
                                      title: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text('${program['program']}'),
                                            if (program['fee_status'] != null)
                                              Chip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  avatar: const Icon(
                                                      Icons.sell_outlined,
                                                      size: 15),
                                                  label: Text(
                                                      '${program['fee_status']}')),
                                            if (program['language'] != null)
                                              Chip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  avatar: const Icon(
                                                      Icons.language_outlined,
                                                      size: 15),
                                                  label: Text(
                                                      '${program['language']}'))
                                          ]),
                                      subtitle: Text(
                                          '${program['university']} • ${program['city'] ?? ''}'),
                                      trailing: Wrap(children: [
                                        IconButton(
                                            tooltip: 'Tercih listesine ekle',
                                            onPressed: () =>
                                                addProgram(program),
                                            icon:
                                                const Icon(Icons.playlist_add)),
                                        IconButton(
                                            tooltip: 'Favorilerden çıkar',
                                            onPressed: () async {
                                              await toggleFavorite(program);
                                              setDialogState(() {});
                                            },
                                            icon:
                                                const Icon(Icons.star_outline))
                                      ]));
                                })),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Kapat'))
                    ])));
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
    Future.microtask(loadFavorites);
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    search.dispose();
    university.dispose();
    city.dispose();
    minRank.dispose();
    maxRank.dispose();
    minQuota.dispose();
    super.dispose();
  }

  Widget multiSelectFilter(
      String label, List<String> options, Set<String> selected,
      {double width = 260}) {
    return SizedBox(
        width: width,
        child: InputDecorator(
            decoration: InputDecoration(
                labelText: label,
                helperText: selected.isEmpty
                    ? 'Tümü'
                    : '${selected.length} seçenek seçildi'),
            child: Wrap(
                spacing: 5,
                runSpacing: 4,
                children: options
                    .map((option) => FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(option),
                        selected: selected.contains(option),
                        onSelected: (checked) => setState(() {
                              if (checked) {
                                selected.add(option);
                              } else {
                                selected.remove(option);
                              }
                            })))
                    .toList())));
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: SearchBar(
                  controller: search,
                  hintText: 'Program, üniversite veya fakülte ara',
                  onChanged: scheduleSearch,
                  onSubmitted: (_) {
                    searchDebounce?.cancel();
                    load(resetPage: true);
                  },
                  leading: const Icon(Icons.search))),
          const SizedBox(width: 12),
          DropdownButton<String>(
              value: level,
              hint: const Text('Tümü'),
              items: const [
                DropdownMenuItem<String>(value: null, child: Text('Tümü')),
                DropdownMenuItem(value: 'lisans', child: Text('Lisans')),
                DropdownMenuItem(value: 'on_lisans', child: Text('Ön lisans'))
              ],
              onChanged: (v) {
                setState(() => level = v);
                load(resetPage: true);
              }),
          IconButton(
              tooltip: 'Sonuçları yenile',
              onPressed: () => load(resetPage: true),
              icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
          Badge(
              label: Text('${ref.watch(preferenceBasketProvider).length}'),
              isLabelVisible: ref.watch(preferenceBasketProvider).isNotEmpty,
              child: IconButton.filledTonal(
                  tooltip: 'Tercih listesine git',
                  onPressed: () => context.go('/tercih'),
                  icon: const Icon(Icons.format_list_numbered))),
          const SizedBox(width: 8),
          Badge(
              label: Text('${favorites.length}'),
              isLabelVisible: favorites.isNotEmpty,
              child: IconButton.filledTonal(
                  tooltip: 'Favori programlar',
                  onPressed: showFavorites,
                  icon: const Icon(Icons.star_outline)))
        ]),
        SizedBox(
            height: 3, child: loading ? const LinearProgressIndicator() : null),
        const SizedBox(height: 12),
        Card(
            color: const Color(0xfffff0e6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xfff0c9b4), width: 1.5)),
            child: ExpansionTile(
                leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: const Color(0xffffd9c5),
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.tune, color: Color(0xffa85f41))),
                title: const Text('Gelişmiş filtreler',
                    style: TextStyle(
                        color: Color(0xff874c36), fontWeight: FontWeight.w800)),
                subtitle: const Text(
                    'Puan türü, üniversite, bölge ve kontenjan seçenekleri',
                    style: TextStyle(color: Color(0xff9a6856))),
                iconColor: const Color(0xffa85f41),
                collapsedIconColor: const Color(0xffa85f41),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    SizedBox(
                        width: 260,
                        child: TextField(
                            controller: university,
                            onSubmitted: (_) => load(resetPage: true),
                            decoration: const InputDecoration(
                                labelText: 'Üniversite adı',
                                prefixIcon:
                                    Icon(Icons.account_balance_outlined)))),
                    SizedBox(
                        width: 180,
                        child: TextField(
                            controller: city,
                            decoration:
                                const InputDecoration(labelText: 'Şehir'))),
                    SizedBox(
                        width: 390,
                        child: InputDecorator(
                            decoration: const InputDecoration(
                                labelText: 'Puan türleri'),
                            child: Wrap(spacing: 6, runSpacing: 4, children: [
                              for (final type in const [
                                'TYT',
                                'SAY',
                                'EA',
                                'SÖZ',
                                'DİL'
                              ])
                                FilterChip(
                                    label: Text(type),
                                    backgroundColor: scoreTypeColor(type)
                                        .withValues(alpha: 0.16),
                                    selectedColor: scoreTypeColor(type)
                                        .withValues(alpha: 0.38),
                                    side: BorderSide(
                                        color: scoreTypeColor(type)
                                            .withValues(alpha: 0.48)),
                                    labelStyle: TextStyle(
                                        color: scoreTypeColor(type),
                                        fontWeight: FontWeight.w800),
                                    checkmarkColor: scoreTypeColor(type),
                                    selected: scoreTypes.contains(type),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          scoreTypes.add(type);
                                        } else {
                                          scoreTypes.remove(type);
                                        }
                                      });
                                      load(resetPage: true);
                                    })
                            ]))),
                    multiSelectFilter('2025 yerleşme durumu',
                        const ['Yeni', 'Dolmadı', 'Yer.Olmadı'], statuses),
                    multiSelectFilter(
                        'Üniversite türü',
                        const ['DEVLET', 'VAKIF', 'KKTC', 'YURTDIŞI'],
                        universityTypes),
                    multiSelectFilter(
                        'Burs / ücret',
                        const [
                          'Burslu',
                          '%50 İndirimli',
                          '%25 İndirimli',
                          'Ücretli'
                        ],
                        feeStatuses,
                        width: 330),
                    multiSelectFilter(
                        'Eğitim dili',
                        const [
                          'Türkçe',
                          'İngilizce',
                          'Almanca',
                          'Fransızca',
                          'Arapça'
                        ],
                        languages,
                        width: 330),
                    multiSelectFilter(
                        'Öğretim türü',
                        const ['Örgün', 'İkinci Öğretim', 'Uzaktan'],
                        educationTypes,
                        width: 300),
                    SizedBox(
                        width: 150,
                        child: TextField(
                            controller: minRank,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'En iyi sıra'))),
                    SizedBox(
                        width: 150,
                        child: TextField(
                            controller: maxRank,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'En düşük sıra'))),
                    SizedBox(
                        width: 150,
                        child: TextField(
                            controller: minQuota,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Minimum kontenjan'))),
                    FilterChip(
                        selected: accreditedOnly,
                        label: const Text('Akredite'),
                        avatar: const Icon(Icons.verified_outlined),
                        onSelected: (v) => setState(() => accreditedOnly = v)),
                    FilterChip(
                        selected: schoolTopOnly,
                        label: const Text('Okul birinciliği kontenjanı'),
                        avatar: const Icon(Icons.workspace_premium_outlined),
                        onSelected: (v) => setState(() => schoolTopOnly = v)),
                    FilterChip(
                        selected: martyrVeteranOnly,
                        label: const Text('Şehit/gazi yakını kontenjanı'),
                        avatar: const Icon(Icons.shield_outlined),
                        onSelected: (v) =>
                            setState(() => martyrVeteranOnly = v)),
                    FilterChip(
                        selected: women34Only,
                        label: const Text('34 yaş üstü kadın kontenjanı'),
                        avatar: const Icon(Icons.woman_outlined),
                        onSelected: (v) => setState(() => women34Only = v)),
                    SizedBox(
                        width: 720,
                        child: Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            child: ExpansionTile(
                                leading: const Icon(Icons.public),
                                title: const Text('Bölge seçimi'),
                                subtitle: Text(regions.isEmpty
                                    ? 'Tüm bölgeler'
                                    : '${regions.length} bölge seçildi'),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                  Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: const [
                                        'MARMARA',
                                        'EGE',
                                        'AKDENİZ',
                                        'İÇ ANADOLU',
                                        'KARADENİZ',
                                        'DOĞU ANADOLU',
                                        'GÜNEY DOĞU',
                                        'KKTC',
                                        'YURT DIŞI'
                                      ]
                                          .map((region) => FilterChip(
                                              showCheckmark: true,
                                              label: Text(region),
                                              selected:
                                                  regions.contains(region),
                                              onSelected: (selected) =>
                                                  setState(() {
                                                    if (selected) {
                                                      regions.add(region);
                                                    } else {
                                                      regions.remove(region);
                                                    }
                                                  })))
                                          .toList())
                                ]))),
                    FilledButton.icon(
                        onPressed: () => load(resetPage: true),
                        icon: const Icon(Icons.filter_alt),
                        label: const Text('Uygula')),
                    TextButton(
                        onPressed: () {
                          city.clear();
                          university.clear();
                          minRank.clear();
                          maxRank.clear();
                          minQuota.clear();
                          setState(() {
                            level = null;
                            scoreTypes.clear();
                            statuses.clear();
                            universityTypes.clear();
                            feeStatuses.clear();
                            languages.clear();
                            educationTypes.clear();
                            regions.clear();
                            accreditedOnly = false;
                            schoolTopOnly = false;
                            martyrVeteranOnly = false;
                            women34Only = false;
                          });
                          load(resetPage: true);
                        },
                        child: const Text('Filtreleri temizle'))
                  ])
                ])),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('$total program bulundu')),
          if (items.isNotEmpty)
            TextButton.icon(
                onPressed: () => setState(() {
                      final visibleIds =
                          items.map<int>((item) => item['id'] as int).toSet();
                      if (visibleIds.every(selectedProgramIds.contains)) {
                        selectedProgramIds.removeAll(visibleIds);
                      } else {
                        selectedProgramIds.addAll(visibleIds);
                      }
                    }),
                icon: Icon(items.isNotEmpty &&
                        items
                            .map<int>((item) => item['id'] as int)
                            .every(selectedProgramIds.contains)
                    ? Icons.deselect
                    : Icons.select_all),
                label: const Text('Sayfadakilerin tümünü seç')),
          if (selectedProgramIds.isNotEmpty)
            FilledButton.icon(
                onPressed: addSelectedPrograms,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(
                    '${selectedProgramIds.length} programı tercih listesine ekle')),
          const SizedBox(width: 12),
          if (total > 0)
            Text(
                '${(page - 1) * pageSize + 1}–${(page - 1) * pageSize + items.length} arası gösteriliyor')
        ]),
        const SizedBox(height: 8),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : loadError != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off, size: 48),
                        const SizedBox(height: 12),
                        Text(loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tekrar dene'))
                      ]))
                    : items.isEmpty
                        ? const Center(
                            child: Text('Filtrelere uygun program bulunamadı.'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = items[i];
                              return ListTile(
                                leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Checkbox(
                                          value: selectedProgramIds
                                              .contains(p['id']),
                                          onChanged: (selected) => setState(() {
                                                if (selected == true) {
                                                  selectedProgramIds
                                                      .add(p['id']);
                                                } else {
                                                  selectedProgramIds
                                                      .remove(p['id']);
                                                }
                                              })),
                                      CircleAvatar(
                                          backgroundColor: scoreTypeColor(
                                              '${p['score_type'] ?? ''}'),
                                          foregroundColor: Colors.white,
                                          child: Text(
                                              '${p['score_type'] ?? '?'}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800)))
                                    ]),
                                title: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text('${p['program']}'),
                                      if (p['kktc_national_only'] == true)
                                        const Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: Icon(Icons.badge_outlined,
                                                size: 16),
                                            label: Text('KKTC Uyruklu')),
                                      if (p['fee_status'] != null)
                                        Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: const Icon(
                                                Icons.sell_outlined,
                                                size: 16),
                                            label: Text('${p['fee_status']}')),
                                      if (p['language'] != null)
                                        Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: const Icon(
                                                Icons.language_outlined,
                                                size: 16),
                                            label: Text('${p['language']}')),
                                      if (kpssDisplay(p['extra']) != '—')
                                        Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: const Icon(
                                                Icons.assessment_outlined,
                                                size: 16),
                                            label: Text(
                                                'KPSS: ${kpssDisplay(p['extra'])}'))
                                    ]),
                                subtitle: Text(
                                    '${p['university']} • ${p['city'] ?? ''}\n'
                                    'Sıralama: ${p['min_rank_2025'] == null ? (p['rank_status_2025'] ?? '—') : NumberFormat.decimalPattern('tr').format(p['min_rank_2025'])} • ${p['quota_2026'] ?? '—'} kont.'
                                    '${p['threshold_rank'] == null ? '' : '\nBaraj: İlk ${NumberFormat.decimalPattern('tr').format(p['threshold_rank'])}'}'),
                                isThreeLine: true,
                                onTap: () => showProgramDetail(p['id']),
                                trailing: Wrap(spacing: 4, children: [
                                  IconButton(
                                      tooltip: favorites
                                              .any((x) => x['id'] == p['id'])
                                          ? 'Favorilerden çıkar'
                                          : 'Favorilere ekle',
                                      onPressed: () => toggleFavorite(p),
                                      icon: Icon(
                                          favorites.any(
                                                  (x) => x['id'] == p['id'])
                                              ? Icons.star
                                              : Icons.star_outline,
                                          color: favorites.any(
                                                  (x) => x['id'] == p['id'])
                                              ? Colors.amber
                                              : null)),
                                  FilledButton.tonalIcon(
                                      onPressed: () => addProgram(p),
                                      icon: const Icon(Icons.playlist_add),
                                      label: const Text('Tercihe ekle')),
                                  PopupMenuButton<String>(
                                      tooltip: 'Diğer işlemler',
                                      onSelected: (value) {
                                        if (value == 'preference') {
                                          addProgram(p);
                                          return;
                                        }
                                        final provider = comparisonProvider;
                                        final current = ref.read(provider);
                                        if (current
                                            .any((x) => x['id'] == p['id'])) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Bu program listede zaten bulunuyor.')));
                                          return;
                                        }
                                        if (value == 'compare' &&
                                            current.length >= 4) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Aynı anda en fazla dört program karşılaştırılabilir.')));
                                          return;
                                        }
                                        ref.read(provider.notifier).state = [
                                          ...current,
                                          Map<String, dynamic>.from(p)
                                        ];
                                      },
                                      itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: 'preference',
                                                child: ListTile(
                                                    leading: Icon(
                                                        Icons.playlist_add),
                                                    title: Text(
                                                        'Tercih listesine ekle'))),
                                            PopupMenuItem(
                                                value: 'compare',
                                                child: ListTile(
                                                    leading: Icon(
                                                        Icons.compare_arrows),
                                                    title: Text(
                                                        'Karşılaştırmaya ekle')))
                                          ]),
                                ]),
                              );
                            })),
        if (loadError == null && total > pageSize)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                OutlinedButton.icon(
                    onPressed: loading || page <= 1
                        ? null
                        : () {
                            setState(() => page--);
                            load();
                          },
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Önceki')),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        '$page / ${((total + pageSize - 1) / pageSize).floor()}')),
                FilledButton.tonalIcon(
                    onPressed: loading || page * pageSize >= total
                        ? null
                        : () {
                            setState(() => page++);
                            load();
                          },
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Sonraki'))
              ]))
      ]));

  Future<void> showProgramDetail(int programId) async {
    final response =
        await ref.read(dioProvider).get('/api/programs/$programId');
    if (!mounted) return;
    final program = response.data as Map;
    final history = (program['rank_history'] as List)
        .map<Map<String, dynamic>>((x) => Map<String, dynamic>.from(x))
        .toList();
    final conditionDetails =
        ((program['special_condition_details'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text('${program['program']}'),
                content: SizedBox(
                    width: 780,
                    child: ListView(shrinkWrap: true, children: [
                      Text('${program['university']} • ${program['faculty']}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(label: Text('${program['city'] ?? '—'}')),
                        if (program['kktc_national_only'] == true)
                          const Chip(
                              avatar: Icon(Icons.badge_outlined, size: 18),
                              label: Text('KKTC Uyruklu')),
                        Chip(label: Text('${program['score_type'] ?? '—'}')),
                        Chip(label: Text('${program['language'] ?? '—'}')),
                        if (program['fee_status'] != null)
                          Chip(
                              avatar: const Icon(Icons.sell_outlined, size: 18),
                              label: Text('${program['fee_status']}')),
                        Chip(
                            label:
                                Text('${program['quota_2026'] ?? '—'} kont.')),
                        if (program['threshold_rank'] != null)
                          Chip(
                              avatar: const Icon(Icons.rule_outlined, size: 18),
                              label: Text(
                                  'Baraj: İlk ${NumberFormat.decimalPattern('tr').format(program['threshold_rank'])}')),
                        if (program['accreditation'] != null)
                          Chip(
                              avatar: const Icon(Icons.verified, size: 18),
                              label: Text('${program['accreditation']}'))
                      ]),
                      const SizedBox(height: 12),
                      Text('Puan ve kontenjan bilgileri',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(
                            avatar: const Icon(Icons.south, size: 18),
                            label: Text(
                                '2025 taban puan: ${program['min_score_2025'] == null ? '—' : NumberFormat('0.000', 'tr').format(program['min_score_2025'])}')),
                        Chip(
                            avatar: const Icon(Icons.north, size: 18),
                            label: Text(
                                '2025 tavan puan: ${program['max_score_2025'] == null ? '—' : NumberFormat('0.000', 'tr').format(program['max_score_2025'])}')),
                        Chip(
                            label: Text(
                                'Okul birinciliği kontenjanı: ${program['school_top_quota'] ?? 'Yok'}')),
                        if (program['school_top_quota'] != null &&
                            program['school_top_quota'] > 0)
                          Chip(
                              avatar:
                                  const Icon(Icons.score_outlined, size: 18),
                              label: Text(
                                  'Okul birinciliği taban puanı: ${program['extra']?['school_top_min_score_2025'] == null ? '—' : NumberFormat('0.000', 'tr').format(program['extra']['school_top_min_score_2025'])}')),
                        if (program['school_top_quota'] != null &&
                            program['school_top_quota'] > 0)
                          Chip(
                              avatar: const Icon(Icons.leaderboard_outlined,
                                  size: 18),
                              label: Text(
                                  'Okul birinciliği başarı sırası: ${program['extra']?['school_top_min_rank_2025'] == null ? '—' : NumberFormat.decimalPattern('tr').format(program['extra']['school_top_min_rank_2025'])}')),
                        Chip(
                            label: Text(
                                'Şehit/gazi yakını kontenjanı: ${program['martyr_veteran_quota'] ?? 'Yok'}')),
                        Chip(
                            label: Text(
                                '34 yaş üstü kadın kontenjanı: ${program['women_34_quota'] ?? 'Yok'}'))
                      ]),
                      if (program['level'] == 'lisans') ...[
                        const SizedBox(height: 12),
                        Text('Akademik kadro',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          Chip(
                              avatar:
                                  const Icon(Icons.school_outlined, size: 18),
                              label: Text(
                                  'Profesör: ${program['extra']?['professors'] ?? '—'}')),
                          Chip(
                              avatar:
                                  const Icon(Icons.school_outlined, size: 18),
                              label: Text(
                                  'Doçent: ${program['extra']?['associate_professors'] ?? '—'}')),
                          Chip(
                              avatar:
                                  const Icon(Icons.school_outlined, size: 18),
                              label: Text(
                                  'Doktor öğretim üyesi: ${program['extra']?['assistant_professors'] ?? '—'}')),
                          Chip(
                              avatar:
                                  const Icon(Icons.groups_outlined, size: 18),
                              label: Text(
                                  'Araştırma görevlisi: ${program['extra']?['research_staff'] ?? '—'}')),
                          Chip(
                              avatar: const Icon(Icons.assessment_outlined,
                                  size: 18),
                              label: Text(
                                  'KPSS puanı: ${kpssDisplay(program['extra'])}'))
                        ])
                      ],
                      const SizedBox(height: 16),
                      Text('2018–2025 Başarı Sırası Geçmişi',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                          height: 220,
                          child: CustomPaint(
                              painter: RankHistoryPainter(history),
                              child: const SizedBox.expand())),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 12,
                          children: history
                              .where((x) => x['rank'] == null)
                              .map((x) => Chip(
                                  label: Text(
                                      '${x['year']}: ${x['status'] ?? 'Veri yok'}')))
                              .toList()),
                      if (program['special_conditions'] != null) ...[
                        const Divider(),
                        Text('Özel koşullar',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('Kodlar: ${program['special_conditions']}'),
                        if (conditionDetails.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...conditionDetails.map((condition) => Card(
                              color: const Color(0xfffff7e8),
                              child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: SelectableText(
                                      'Bk. ${condition['code']}: '
                                      '${condition['description']}'))))
                        ]
                      ]
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Kapat'))
                ]));
  }
}

class RankHistoryPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  RankHistoryPainter(this.history);
  @override
  void paint(Canvas canvas, Size size) {
    final numeric = history.where((x) => x['rank'] is num).toList();
    final axis = Paint()
      ..color = Colors.blueGrey.shade300
      ..strokeWidth = 1;
    final line = Paint()
      ..color = Colors.indigo
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(42, 8), Offset(42, size.height - 28), axis);
    canvas.drawLine(Offset(42, size.height - 28),
        Offset(size.width - 8, size.height - 28), axis);
    if (numeric.length < 2) return;
    final ranks = numeric.map((x) => (x['rank'] as num).toDouble()).toList();
    final minRank = ranks.reduce((a, b) => a < b ? a : b);
    final maxRank = ranks.reduce((a, b) => a > b ? a : b);
    final span = (maxRank - minRank).abs() < 1 ? 1 : maxRank - minRank;
    final path = Path();
    for (var i = 0; i < numeric.length; i++) {
      final x = 42 + i * (size.width - 58) / (numeric.length - 1);
      final normalized = (ranks[i] - minRank) / span;
      final y = 14 + normalized * (size.height - 50);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.indigo);
      final rankLabel = TextPainter(
          text: TextSpan(
              text: NumberFormat.compact(locale: 'tr').format(ranks[i]),
              style: const TextStyle(
                  color: Colors.indigo,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      final labelY = y < 26 ? y + 7 : y - rankLabel.height - 6;
      rankLabel.paint(
          canvas,
          Offset(
              (x - rankLabel.width / 2)
                  .clamp(42.0, size.width - rankLabel.width - 8),
              labelY));
      final text = TextPainter(
          text: TextSpan(
              text: '${numeric[i]['year']}',
              style: const TextStyle(color: Colors.blueGrey, fontSize: 10)),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      text.paint(canvas, Offset(x - text.width / 2, size.height - 22));
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant RankHistoryPainter oldDelegate) =>
      oldDelegate.history != history;
}

class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key});
  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  late Future<Response> students;
  final studentSearch = TextEditingController();
  Timer? studentSearchDebounce;

  @override
  void initState() {
    super.initState();
    students = _loadStudents();
  }

  Future<Response> _loadStudents() =>
      ref.read(dioProvider).get('/api/students', queryParameters: {
        'q':
            studentSearch.text.trim().isEmpty ? null : studentSearch.text.trim()
      });

  @override
  void dispose() {
    studentSearchDebounce?.cancel();
    studentSearch.dispose();
    super.dispose();
  }

  void scheduleStudentSearch(String _) {
    studentSearchDebounce?.cancel();
    studentSearchDebounce = Timer(const Duration(milliseconds: 350), reload);
  }

  void reload() {
    setState(() {
      students = _loadStudents();
    });
  }

  String formatPreferenceDate(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return 'Tarih bilinmiyor';
    try {
      return DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
    } catch (_) {
      final local = parsed.toLocal();
      String twoDigits(int number) => number.toString().padLeft(2, '0');
      return '${twoDigits(local.day)}.${twoDigits(local.month)}.${local.year} '
          '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
    }
  }

  Future<void> showPreferenceHistory(Map student) async {
    final history = (student['preference_history'] as List?) ?? [];
    await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(
                    '${student['first_name']} ${student['last_name']} • Tercih geçmişi'),
                content: SizedBox(
                    width: 620,
                    height: 420,
                    child: history.isEmpty
                        ? const Center(
                            child: Text('Henüz tercih çalışması kaydedilmedi.'))
                        : ListView.separated(
                            itemCount: history.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final item = history[index];
                              return ListTile(
                                  leading: CircleAvatar(
                                      child: Text('${history.length - index}')),
                                  title: Text('${item['name']}'),
                                  subtitle: Text(
                                      '${formatPreferenceDate(item['created_at'])} • Sürüm ${item['version']}'),
                                  trailing: Text(item['status'] == 'completed'
                                      ? 'Tamamlandı'
                                      : item['status'] == 'archived'
                                          ? 'Arşiv'
                                          : 'Taslak'));
                            })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Kapat'))
                ]));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
      future: students,
      builder: (_, s) {
        final unauthorized = s.error is DioException &&
            (s.error as DioException).response?.statusCode == 401;
        if (s.hasError && (ref.watch(tokenProvider) == null || unauthorized)) {
          return Center(
              child: FilledButton.icon(
                  onPressed: () => context.go('/giris'),
                  icon: const Icon(Icons.login),
                  label: const Text('Öğrenciler için giriş yap')));
        }
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
              child: FilledButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Öğrenci listesini tekrar yükle')));
        }
        final list = (s.data?.data as List?) ?? [];
        return Scaffold(
            body: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                Expanded(
                    child: Text('Öğrenciler',
                        style: Theme.of(context).textTheme.headlineMedium)),
                OutlinedButton.icon(
                    onPressed: _showArchivedStudents,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Arşiv'))
              ]),
              const SizedBox(height: 12),
              SearchBar(
                  controller: studentSearch,
                  hintText: 'Ad, soyad, okul, telefon veya e-posta ile ara',
                  leading: const Icon(Icons.search),
                  onChanged: scheduleStudentSearch,
                  onSubmitted: (_) {
                    studentSearchDebounce?.cancel();
                    reload();
                  },
                  trailing: [
                    if (studentSearch.text.isNotEmpty)
                      IconButton(
                          tooltip: 'Aramayı temizle',
                          onPressed: () {
                            studentSearch.clear();
                            reload();
                          },
                          icon: const Icon(Icons.close))
                  ]),
              const SizedBox(height: 14),
              if (list.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: Text(studentSearch.text.trim().isEmpty
                            ? 'Henüz öğrenci kaydı yok.'
                            : 'Aramanıza uygun öğrenci bulunamadı.'))),
              ...list.map((x) => Card(
                  child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text('${x['first_name']} ${x['last_name']}'),
                      subtitle: Text([
                        x['school'],
                        x['graduation_status'],
                        x['phone'],
                        'Tercih çalışması: ${x['preference_count'] ?? 0}'
                            '${((x['preference_history'] as List?) ?? []).isEmpty ? '' : ' • Son: ${formatPreferenceDate(x['preference_history'][0]['created_at'])}'}'
                      ].where((v) => v != null && '$v'.isNotEmpty).join(' • ')),
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(
                            tooltip:
                                'Tercih tarihleri (${x['preference_count'] ?? 0})',
                            icon: Badge(
                                isLabelVisible:
                                    (x['preference_count'] ?? 0) > 0,
                                label: Text('${x['preference_count'] ?? 0}'),
                                child: const Icon(Icons.event_note_outlined)),
                            onPressed: () => showPreferenceHistory(x)),
                        IconButton(
                            tooltip: 'Öğrenci bilgilerini düzenle',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final changed = await _studentForm(context, x);
                              if (changed) reload();
                            })
                      ]),
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => StudentNotesDialog(
                              studentId: x['id'],
                              studentName:
                                  '${x['first_name']} ${x['last_name']}')))))
            ]),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  final added = await _add(context);
                  if (added) reload();
                },
                icon: const Icon(Icons.add),
                label: const Text('Öğrenci ekle')));
      });
  Future<bool> _add(BuildContext context) async {
    return _studentForm(context, null);
  }

  Future<bool> _studentForm(BuildContext context, Map? student) async {
    final name = TextEditingController(text: '${student?['first_name'] ?? ''}');
    final surname =
        TextEditingController(text: '${student?['last_name'] ?? ''}');
    final school = TextEditingController(text: '${student?['school'] ?? ''}');
    final phone = TextEditingController(text: '${student?['phone'] ?? ''}');
    final email = TextEditingController(text: '${student?['email'] ?? ''}');
    const scoreTypes = ['TYT', 'SAY', 'EA', 'SÖZ', 'DİL'];
    final scoreControllers = {
      for (final type in scoreTypes) type: TextEditingController()
    };
    final resultRankControllers = {
      for (final type in scoreTypes) type: TextEditingController()
    };
    String? graduationStatus = student?['graduation_status'];
    bool consentGiven = student?['consent_given'] == true;
    String? formError;
    if (student != null) {
      try {
        final response = await ref
            .read(dioProvider)
            .get('/api/students/${student['id']}/exam-results');
        for (final result in response.data as List) {
          final type = '${result['score_type']}';
          if (!scoreControllers.containsKey(type) || result['year'] != 2026) {
            continue;
          }
          if (result['score'] != null) {
            scoreControllers[type]!.text =
                '${result['score']}'.replaceAll('.', ',');
          }
          if (result['rank'] != null) {
            resultRankControllers[type]!.text =
                NumberFormat.decimalPattern('tr').format(result['rank']);
          }
        }
      } on DioException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${e.response?.data['detail'] ?? 'YKS sonuçları yüklenemedi.'}')));
        }
        return false;
      }
    }
    if (!context.mounted) return false;
    final saved = await showDialog<bool>(
            context: context,
            builder: (c) => StatefulBuilder(
                builder: (c, setDialogState) => AlertDialog(
                        title: Text(student == null
                            ? 'Yeni öğrenci'
                            : 'Öğrenci bilgilerini düzenle'),
                        content: SizedBox(
                            width: 760,
                            child: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: TextField(
                                            controller: name,
                                            decoration: const InputDecoration(
                                                labelText: 'Ad *'))),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: TextField(
                                            controller: surname,
                                            decoration: const InputDecoration(
                                                labelText: 'Soyad *')))
                                  ]),
                                  TextField(
                                      controller: school,
                                      decoration: const InputDecoration(
                                          labelText: 'Okul')),
                                  DropdownButtonFormField<String>(
                                      initialValue: graduationStatus,
                                      decoration: const InputDecoration(
                                          labelText: 'Öğrenim durumu'),
                                      items: const [
                                        '12. sınıf',
                                        'Mezun',
                                        'Ara sınıf'
                                      ]
                                          .map((x) => DropdownMenuItem(
                                              value: x, child: Text(x)))
                                          .toList(),
                                      onChanged: (value) => setDialogState(
                                          () => graduationStatus = value)),
                                  Row(children: [
                                    Expanded(
                                        child: TextField(
                                            controller: phone,
                                            decoration: const InputDecoration(
                                                labelText: 'Telefon'))),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: TextField(
                                            controller: email,
                                            decoration: const InputDecoration(
                                                labelText: 'E-posta')))
                                  ]),
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: consentGiven,
                                      title: const Text(
                                          'Kişisel veri işleme onayı alındı'),
                                      onChanged: (value) => setDialogState(
                                          () => consentGiven = value ?? false)),
                                  const SizedBox(height: 8),
                                  Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                          color: const Color(0xfff1edfa),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                              color: const Color(0xffddd6f0))),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('2026 YKS sınav sonuçları',
                                                style: Theme.of(c)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800)),
                                            const SizedBox(height: 4),
                                            const Text(
                                                'Öğrencinin mevcut puan ve başarı sıralamalarını puan türlerine göre girin. Kullanılmayan alanlar boş bırakılabilir.'),
                                            const SizedBox(height: 14),
                                            for (final type in scoreTypes)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 10),
                                                  child: Row(children: [
                                                    CircleAvatar(
                                                        radius: 23,
                                                        backgroundColor:
                                                            scoreTypeColor(
                                                                type),
                                                        foregroundColor:
                                                            Colors.white,
                                                        child: Text(type,
                                                            style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800))),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                        child: TextField(
                                                            controller:
                                                                scoreControllers[
                                                                    type],
                                                            keyboardType:
                                                                const TextInputType
                                                                    .numberWithOptions(
                                                                    decimal:
                                                                        true),
                                                            decoration:
                                                                InputDecoration(
                                                                    labelText:
                                                                        '$type puanı'))),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                        child: TextField(
                                                            controller:
                                                                resultRankControllers[
                                                                    type],
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration:
                                                                InputDecoration(
                                                                    labelText:
                                                                        '$type başarı sırası')))
                                                  ]))
                                          ])),
                                  if (formError != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(formError!,
                                            style: TextStyle(
                                                color: Theme.of(c)
                                                    .colorScheme
                                                    .error)))
                                ]))),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Vazgeç')),
                          FilledButton(
                              onPressed: () async {
                                if (name.text.trim().isEmpty ||
                                    surname.text.trim().isEmpty) {
                                  setDialogState(() =>
                                      formError = 'Ad ve soyad zorunludur.');
                                  return;
                                }
                                final examResults = <Map<String, dynamic>>[];
                                for (final type in scoreTypes) {
                                  final scoreText =
                                      scoreControllers[type]!.text.trim();
                                  final rankText =
                                      resultRankControllers[type]!.text.trim();
                                  if (scoreText.isEmpty && rankText.isEmpty) {
                                    continue;
                                  }
                                  final parsedScore = scoreText.isEmpty
                                      ? null
                                      : double.tryParse(
                                          scoreText.replaceAll(',', '.'));
                                  final parsedRank = rankText.isEmpty
                                      ? null
                                      : int.tryParse(rankText
                                          .replaceAll('.', '')
                                          .replaceAll(' ', ''));
                                  if (scoreText.isNotEmpty &&
                                      (parsedScore == null ||
                                          parsedScore <= 0 ||
                                          parsedScore > 600)) {
                                    setDialogState(() => formError =
                                        '$type puanı 0 ile 600 arasında olmalıdır.');
                                    return;
                                  }
                                  if (rankText.isNotEmpty &&
                                      (parsedRank == null || parsedRank <= 0)) {
                                    setDialogState(() => formError =
                                        '$type başarı sırası pozitif bir sayı olmalıdır.');
                                    return;
                                  }
                                  examResults.add({
                                    'year': 2026,
                                    'score_type': type,
                                    'score': parsedScore,
                                    'rank': parsedRank
                                  });
                                }
                                final data = <String, dynamic>{
                                  'first_name': name.text.trim(),
                                  'last_name': surname.text.trim(),
                                  'school': school.text.trim().isEmpty
                                      ? null
                                      : school.text.trim(),
                                  'graduation_status': graduationStatus,
                                  'phone': phone.text.trim().isEmpty
                                      ? null
                                      : phone.text.trim(),
                                  'email': email.text.trim().isEmpty
                                      ? null
                                      : email.text.trim(),
                                  'consent_given': consentGiven,
                                  'exam_results': examResults
                                };
                                try {
                                  if (student == null) {
                                    await ref.read(dioProvider).post(
                                        '/api/students-with-results',
                                        data: data);
                                  } else {
                                    await ref.read(dioProvider).put(
                                        '/api/students/${student['id']}/with-results',
                                        data: data);
                                  }
                                  if (c.mounted) Navigator.pop(c, true);
                                } on DioException catch (e) {
                                  setDialogState(() => formError =
                                      '${e.response?.data['detail'] ?? 'Öğrenci kaydedilemedi.'}');
                                }
                              },
                              child: const Text('Kaydet'))
                        ]))) ??
        false;
    for (final controller in [
      name,
      surname,
      school,
      phone,
      email,
      ...scoreControllers.values,
      ...resultRankControllers.values
    ]) {
      controller.dispose();
    }
    return saved;
  }

  Future<void> _showArchivedStudents() async {
    try {
      final response =
          await ref.read(dioProvider).get('/api/students/archived');
      if (!mounted) return;
      final rows = response.data as List;
      await showDialog(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                      title: const Text('Arşivlenen öğrenciler'),
                      content: SizedBox(
                          width: 620,
                          height: 420,
                          child: rows.isEmpty
                              ? const Center(
                                  child: Text('Arşivlenmiş öğrenci yok.'))
                              : ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (_, index) {
                                    final student = rows[index];
                                    return ListTile(
                                        leading: const Icon(Icons.person_off),
                                        title: Text(
                                            '${student['first_name']} ${student['last_name']}'),
                                        subtitle:
                                            Text('${student['school'] ?? ''}'),
                                        trailing: FilledButton.tonalIcon(
                                            onPressed: () async {
                                              await ref.read(dioProvider).post(
                                                  '/api/students/${student['id']}/restore');
                                              rows.removeAt(index);
                                              setDialogState(() {});
                                              reload();
                                            },
                                            icon: const Icon(Icons.restore),
                                            label: const Text('Geri al')));
                                  })),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Kapat'))
                      ])));
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${e.response?.data['detail'] ?? 'Arşiv açılamadı.'}')));
    }
  }
}

class StudentNotesDialog extends ConsumerStatefulWidget {
  final int studentId;
  final String studentName;
  const StudentNotesDialog(
      {required this.studentId, required this.studentName, super.key});
  @override
  ConsumerState<StudentNotesDialog> createState() => _StudentNotesDialogState();
}

class _StudentNotesDialogState extends ConsumerState<StudentNotesDialog> {
  final note = TextEditingController();
  late Future<Response> notes;
  @override
  void initState() {
    super.initState();
    notes =
        ref.read(dioProvider).get('/api/students/${widget.studentId}/notes');
  }

  Future<void> addNote() async {
    if (note.text.trim().isEmpty) return;
    await ref.read(dioProvider).post('/api/students/${widget.studentId}/notes',
        data: {'note': note.text});
    note.clear();
    setState(() {
      notes =
          ref.read(dioProvider).get('/api/students/${widget.studentId}/notes');
    });
  }

  Future<void> showExamResults() async {
    var results = await ref
        .read(dioProvider)
        .get('/api/students/${widget.studentId}/exam-results');
    if (!mounted) return;
    String scoreType = 'SAY';
    final score = TextEditingController();
    final rank = TextEditingController();
    String? error;
    await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: const Text('2026 YKS sonuçları'),
                    content: SizedBox(
                        width: 600,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          if ((results.data as List).isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Henüz sınav sonucu girilmedi.'))
                          else
                            ...((results.data as List).map((item) => ListTile(
                                leading: CircleAvatar(
                                    child: Text('${item['score_type']}')),
                                title: Text(
                                    'Başarı sırası: ${item['rank'] ?? '—'}'),
                                subtitle: Text('Puan: ${item['score'] ?? '—'}'),
                                trailing: IconButton(
                                    tooltip: 'Sonucu sil',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      await ref.read(dioProvider).delete(
                                          '/api/students/${widget.studentId}/exam-results/${item['id']}');
                                      results = await ref.read(dioProvider).get(
                                          '/api/students/${widget.studentId}/exam-results');
                                      setDialogState(() {});
                                    })))),
                          const Divider(),
                          Row(children: [
                            SizedBox(
                                width: 130,
                                child: DropdownButtonFormField<String>(
                                    initialValue: scoreType,
                                    decoration: const InputDecoration(
                                        labelText: 'Puan türü'),
                                    items: const [
                                      'TYT',
                                      'SAY',
                                      'EA',
                                      'SÖZ',
                                      'DİL'
                                    ]
                                        .map((x) => DropdownMenuItem(
                                            value: x, child: Text(x)))
                                        .toList(),
                                    onChanged: (value) => setDialogState(
                                        () => scoreType = value!))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextField(
                                    controller: score,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Puan'))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextField(
                                    controller: rank,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Başarı sırası')))
                          ]),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(dialogContext)
                                            .colorScheme
                                            .error)))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Kapat')),
                      FilledButton.icon(
                          onPressed: () async {
                            final parsedRank =
                                int.tryParse(rank.text.replaceAll('.', ''));
                            if (parsedRank == null || parsedRank <= 0) {
                              setDialogState(() =>
                                  error = 'Geçerli bir başarı sırası girin.');
                              return;
                            }
                            try {
                              await ref.read(dioProvider).post(
                                  '/api/students/${widget.studentId}/exam-results',
                                  data: {
                                    'year': 2026,
                                    'score_type': scoreType,
                                    'score': double.tryParse(
                                        score.text.replaceAll(',', '.')),
                                    'rank': parsedRank
                                  });
                              results = await ref.read(dioProvider).get(
                                  '/api/students/${widget.studentId}/exam-results');
                              score.clear();
                              rank.clear();
                              setDialogState(() => error = null);
                            } on DioException catch (e) {
                              setDialogState(() => error =
                                  '${e.response?.data['detail'] ?? 'Sonuç kaydedilemedi.'}');
                            }
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Sonucu kaydet'))
                    ])));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('${widget.studentName} • Görüşme notları'),
          content: SizedBox(
              width: 650,
              height: 480,
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: note,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Yeni görüşme notu'))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      tooltip: 'Notu kaydet',
                      onPressed: addNote,
                      icon: const Icon(Icons.add_comment))
                ]),
                const Divider(),
                Expanded(
                    child: FutureBuilder<Response>(
                        future: notes,
                        builder: (_, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final rows = snapshot.data!.data as List;
                          if (rows.isEmpty) {
                            return const Center(
                                child: Text('Henüz görüşme notu yok.'));
                          }
                          return ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (_, index) {
                                final item = rows[index];
                                return Card(
                                    child: ListTile(
                                        leading: const Icon(
                                            Icons.chat_bubble_outline),
                                        title: Text('${item['note']}'),
                                        subtitle: Text(
                                            '${item['author']} • ${item['created_at']}')));
                              });
                        }))
              ])),
          actions: [
            TextButton.icon(
                onPressed: showExamResults,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('YKS sonuçları')),
            TextButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (confirmContext) => AlertDialog(
                                  title: const Text('Öğrenciyi arşivle'),
                                  content: const Text(
                                      'Öğrenci aktif listelerden kaldırılacak. Devam edilsin mi?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(
                                            confirmContext, false),
                                        child: const Text('Vazgeç')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(confirmContext, true),
                                        child: const Text('Arşivle'))
                                  ])) ??
                      false;
                  if (!confirmed || !mounted) return;
                  await ref
                      .read(dioProvider)
                      .delete('/api/students/${widget.studentId}');
                  if (mounted) navigator.pop();
                },
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Arşivle')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'))
          ]);
}

class PreferencePage extends ConsumerStatefulWidget {
  const PreferencePage({super.key});
  @override
  ConsumerState<PreferencePage> createState() => _PreferencePageState();
}

class _PreferencePageState extends ConsumerState<PreferencePage> {
  int? studentId;
  String scoreType = 'SAY';
  final rankControllers = {
    'TYT': TextEditingController(),
    'SAY': TextEditingController(),
    'EA': TextEditingController(),
    'SÖZ': TextEditingController(),
    'DİL': TextEditingController()
  };
  late final TextEditingController listName;
  Map<int, Map<String, dynamic>> decisions = {};
  bool saving = false;
  bool loadingStudentResults = false;
  bool redirectingToLogin = false;
  late Future<Response> students;
  int? editingListId;

  @override
  void initState() {
    super.initState();
    listName =
        TextEditingController(text: ref.read(preferenceListNameProvider));
    students = ref.read(dioProvider).get('/api/students');
    studentId = ref.read(selectedPreferenceStudentProvider);
    if (studentId != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => loadStudentResults(studentId));
    }
  }

  @override
  void dispose() {
    listName.dispose();
    for (final controller in rankControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> loadStudentResults(int? value) async {
    setState(() {
      studentId = value;
      ref.read(selectedPreferenceStudentProvider.notifier).state = value;
      loadingStudentResults = value != null;
      decisions = {};
      for (final controller in rankControllers.values) {
        controller.clear();
      }
    });
    if (value == null) return;
    try {
      final response =
          await ref.read(dioProvider).get('/api/students/$value/exam-results');
      for (final item in (response.data as List)) {
        if (item['year'] == 2026 &&
            rankControllers.containsKey(item['score_type']) &&
            item['rank'] != null) {
          rankControllers[item['score_type']]!.text =
              NumberFormat.decimalPattern('tr').format(item['rank']);
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['detail'] ??
                'Öğrencinin YKS sonuçları alınamadı.')));
      }
    } finally {
      if (mounted) setState(() => loadingStudentResults = false);
    }
  }

  void handleExpiredSession() {
    if (redirectingToLogin) return;
    redirectingToLogin = true;
    Future.microtask(() async {
      ref.read(tokenProvider.notifier).state = null;
      ref.read(userRoleProvider.notifier).state = null;
      ref.read(dioProvider).options.headers.remove('Authorization');
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('access_token');
      if (mounted) context.go('/giris');
    });
  }

  Future<void> analyze() async {
    final basket = ref.read(preferenceBasketProvider);
    if (ref.read(tokenProvider) == null) {
      context.go('/giris');
      return;
    }
    if (studentId == null || basket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Öğrenci ve en az bir program gereklidir.')));
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      final groupedPrograms = <String, List<int>>{};
      for (final program in basket) {
        final type = '${program['score_type'] ?? ''}';
        if (rankControllers.containsKey(type)) {
          groupedPrograms.putIfAbsent(type, () => []).add(program['id']);
        }
      }
      final missingTypes = groupedPrograms.keys
          .where((type) =>
              int.tryParse(rankControllers[type]!
                  .text
                  .replaceAll('.', '')
                  .replaceAll(' ', '')) ==
              null)
          .toList();
      if (missingTypes.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${missingTypes.join(', ')} başarı sıralamasını girin.')));
        return;
      }
      final allDecisions = <int, Map<String, dynamic>>{};
      for (final entry in groupedPrograms.entries) {
        final response = await dio.post('/api/recommend/batch',
            queryParameters: {'student_id': studentId, 'score_type': entry.key},
            data: entry.value);
        for (final item in response.data['items']) {
          allDecisions[item['program_id'] as int] =
              Map<String, dynamic>.from(item);
        }
      }
      setState(() {
        decisions = allDecisions;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Programlar öğrencinin sırasına göre analiz edildi.')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.data['detail'] ?? 'Analiz yapılamadı.')));
      }
    }
  }

  Future<void> save() async {
    final basket = ref.read(preferenceBasketProvider);
    if (ref.read(tokenProvider) == null) {
      context.go('/giris');
      return;
    }
    if (studentId == null || basket.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Öğrenci seçin ve en az bir program ekleyin.')));
      return;
    }
    setState(() => saving = true);
    try {
      final types = basket
          .map((x) => '${x['score_type'] ?? ''}')
          .where((x) => x.isNotEmpty)
          .toSet();
      scoreType = types.length == 1 ? types.first : 'KARMA';
      final payload = {
        'student_id': studentId,
        'name': listName.text.trim().isEmpty
            ? '2026 YKS Tercih Listesi'
            : listName.text.trim(),
        'score_type': scoreType,
        'items': [
          for (var i = 0; i < basket.length; i++)
            {
              'program_id': basket[i]['id'],
              'position': i + 1,
              'category': decisions[basket[i]['id']]?['category'] ??
                  'Değerlendirilecek',
              'explanation': decisions[basket[i]['id']]?['explanation']
            }
        ]
      };
      final creatingList = editingListId == null;
      final response = creatingList
          ? await ref
              .read(dioProvider)
              .post('/api/preference-lists', data: payload)
          : await ref.read(dioProvider).put(
              '/api/preference-lists/$editingListId',
              data: {'name': payload['name'], 'items': payload['items']});
      if (mounted) {
        final savedListId = editingListId ?? response.data['id'] as int;
        setState(() => editingListId = savedListId);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(creatingList
                ? 'Tercih listesi #${response.data['id']} taslak olarak kaydedildi.'
                : 'Tercih listesi güncellendi.')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.response?.data['detail'] ?? 'Liste kaydedilemedi.')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Color? decisionColor(Map<String, dynamic>? decision) {
    switch (decision?['category']) {
      case 'Baraj dışı':
        return Colors.red;
      case 'Yüksek hedef':
        return Colors.orange;
      case 'Hedef aralığı':
      case 'Dengeli':
      case 'Daha güvenli':
        return Colors.green;
      default:
        return null;
    }
  }

  IconData decisionIcon(Map<String, dynamic>? decision) {
    switch (decision?['category']) {
      case 'Baraj dışı':
        return Icons.block;
      case 'Yüksek hedef':
        return Icons.warning_amber_rounded;
      case 'Hedef aralığı':
        return Icons.track_changes;
      case 'Dengeli':
        return Icons.check_circle_outline;
      case 'Daha güvenli':
        return Icons.verified_user_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> clearPreferenceList() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Tercih listesi boşaltılsın mı?'),
              content: const Text(
                  'Mevcut taslaktaki programlar temizlenecek. Öğrenci bilgileri ve daha önce kaydedilen listeler silinmeyecek.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Vazgeç')),
                FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Listeyi boşalt'))
              ]),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    ref.read(preferenceBasketProvider.notifier).state = [];
    setState(() {
      decisions = {};
      editingListId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Tercih listesi boşaltıldı. Öğrenci ve kayıtlı listeler korundu.')));
  }

  Future<void> clearPreferenceForm() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.restart_alt),
              title: const Text('Formun tamamı temizlensin mi?'),
              content: const Text(
                  'Tercihler, seçili öğrenci, liste adı, başarı sıralamaları ve analiz sonuçları sıfırlanacak. Kayıtlı öğrenciler ve daha önce kaydedilmiş tercih listeleri silinmeyecek.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Vazgeç')),
                FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Formu temizle'))
              ]),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    const defaultListName = '2026 YKS Tercih Listesi';
    ref.read(preferenceBasketProvider.notifier).state = [];
    ref.read(selectedPreferenceStudentProvider.notifier).state = null;
    ref.read(preferenceListNameProvider.notifier).state = defaultListName;
    for (final controller in rankControllers.values) {
      controller.clear();
    }
    listName.text = defaultListName;
    setState(() {
      studentId = null;
      scoreType = 'SAY';
      decisions = {};
      editingListId = null;
      loadingStudentResults = false;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Tercih formu temizlendi. Kayıtlı öğrenciler ve listeler korundu.')));
  }

  dynamic rankValue(Map<String, dynamic> program, int year) {
    final direct = program['rank_$year'];
    if (direct != null && '$direct'.trim().isNotEmpty) return direct;
    if (year == 2025) {
      return program['min_rank_2025'] ?? program['rank_status_2025'];
    }
    final history = (program['rank_history'] as List?) ?? const [];
    for (final item in history) {
      if (item is Map && item['year'] == year) {
        return item['rank'] ?? item['status'];
      }
    }
    return null;
  }

  Future<void> showPreferenceProgramDetail(
      Map<String, dynamic> basketProgram) async {
    Map<String, dynamic> program = Map<String, dynamic>.from(basketProgram);
    try {
      if (program['id'] != null) {
        final response =
            await ref.read(dioProvider).get('/api/programs/${program['id']}');
        program = Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {
      // Bağlantı yoksa sepette bulunan bilgiler yine de gösterilir.
    }
    if (!mounted) return;
    final history = ((program['rank_history'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort((a, b) => ((b['year'] as num?)?.toInt() ?? 0)
          .compareTo((a['year'] as num?)?.toInt() ?? 0));
    final extra = program['extra'] is Map
        ? Map<String, dynamic>.from(program['extra'])
        : <String, dynamic>{};
    final conditionDetails =
        ((program['special_condition_details'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

    Widget detail(String label, dynamic value, {bool highlight = false}) =>
        Container(
            width: 230,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: highlight
                    ? const Color(0xfffff0c9)
                    : const Color(0xfff5f2fb),
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xff655d73))),
              const SizedBox(height: 3),
              SelectableText(tableValue(value),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13))
            ]));

    await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('${program['program'] ?? 'Program detayı'}'),
              content: SizedBox(
                  width: 820,
                  child: ListView(shrinkWrap: true, children: [
                    Text(
                        '${program['university'] ?? '—'} • ${program['faculty'] ?? '—'}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('${program['city'] ?? '—'}'),
                    if (program['kktc_national_only'] == true)
                      const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                  avatar: Icon(Icons.badge_outlined, size: 18),
                                  label: Text('KKTC Uyruklu')))),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      detail('Program kodu', program['program_code']),
                      detail('Puan türü', program['score_type']),
                      detail('Program düzeyi', program['level']),
                      detail('Öğrenim türü', program['education_type']),
                      detail('Öğrenim süresi', program['duration']),
                      detail('Öğretim dili', program['language']),
                      detail('Ücret durumu', program['fee_status']),
                      detail('2026 kontenjanı', program['quota_2026']),
                      detail(
                          '2025 taban başarı sırası', rankValue(program, 2025),
                          highlight: true),
                      detail('2025 taban puanı', program['min_score_2025'],
                          highlight: true),
                      detail('2025 tavan puanı', program['max_score_2025']),
                      detail('Başarı sırası barajı', program['threshold_rank']),
                      detail('Okul birinciliği kontenjanı',
                          program['school_top_quota']),
                      detail('Okul birinciliği taban sırası',
                          extra['school_top_min_rank_2025']),
                      detail('Okul birinciliği taban puanı',
                          extra['school_top_min_score_2025']),
                      detail('Şehit/gazi yakını kontenjanı',
                          program['martyr_veteran_quota']),
                      detail('34 yaş üstü kadın kontenjanı',
                          program['women_34_quota']),
                      detail('Akreditasyon', program['accreditation']),
                      detail('Profesör', extra['professors']),
                      detail('Doçent', extra['associate_professors']),
                      detail('Doktor öğretim üyesi',
                          extra['assistant_professors']),
                      detail('Araştırma görevlisi', extra['research_staff']),
                      detail('KPSS puanı', kpssDisplay(extra),
                          highlight: extra['kpss'] != null),
                    ]),
                    if (history.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Başarı sırası geçmişi',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: history
                              .map((item) => Chip(
                                  label: Text(
                                      '${item['year']}: ${tableValue(item['rank'] ?? item['status'])}')))
                              .toList())
                    ],
                    if (tableValue(program['special_conditions']) != '—') ...[
                      const SizedBox(height: 18),
                      Text('Özel koşullar',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(
                          'Kodlar: ${program['special_conditions']}'),
                      if (conditionDetails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...conditionDetails.map((condition) => Card(
                            color: const Color(0xfffff7e8),
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child:
                                    SelectableText('Bk. ${condition['code']}: '
                                        '${condition['description']}'))))
                      ]
                    ]
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Kapat'))
              ],
            ));
  }

  String tableValue(dynamic value, {bool decimal = false}) {
    if (value == null || '$value'.trim().isEmpty) return '—';
    if (decimal && value is num) {
      return NumberFormat('0.000', 'tr').format(value);
    }
    if (value is int) return NumberFormat.decimalPattern('tr').format(value);
    return '$value';
  }

  Widget preferenceCell(String text, double width,
          {bool bold = false,
          int maxLines = 3,
          TextAlign align = TextAlign.left,
          Color? color}) =>
      SizedBox(
          width: width,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Tooltip(
                  message: text,
                  child: Text(text,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: align,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight:
                              bold ? FontWeight.w800 : FontWeight.w500)))));

  Widget preferenceTableHeader() => Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
          color: const Color(0xffe4def5),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        preferenceCell('Sıra', 46, bold: true, align: TextAlign.center),
        preferenceCell('Program kodu', 88, bold: true),
        preferenceCell('Program / Üniversite', 240, bold: true),
        preferenceCell('Tür', 58, bold: true),
        preferenceCell('Öğrenim', 82, bold: true),
        preferenceCell('Süre', 54, bold: true),
        preferenceCell('Dil', 78, bold: true),
        preferenceCell('Ücret', 92, bold: true),
        preferenceCell('2025 sıra', 86, bold: true),
        preferenceCell('2024 sıra', 86, bold: true),
        preferenceCell('2025 puan', 88, bold: true),
        preferenceCell('2026 kont.', 72, bold: true),
        preferenceCell('Özel koşullar', 145, bold: true),
        preferenceCell('Akreditasyon', 92, bold: true),
        preferenceCell('KPSS', 76, bold: true),
        preferenceCell('İşlem', 76, bold: true, align: TextAlign.center),
      ]));

  Widget preferenceTableRow(
      Map<String, dynamic> program,
      int index,
      Map<String, dynamic>? decision,
      Color? statusColor,
      VoidCallback? onDelete,
      {bool reorderable = true}) {
    final education = '${program['education_type'] ?? '—'}';
    final extraEducation =
        education.toLowerCase().contains('açık') ? 'Açıköğretim' : education;
    return Card(
        key: ValueKey(program['id']),
        color: statusColor?.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: statusColor?.withValues(alpha: 0.65) ??
                    Theme.of(context).colorScheme.outlineVariant,
                width: statusColor == null ? 1 : 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showPreferenceProgramDetail(program),
          child: SizedBox(
              height: 88,
              child: Row(children: [
                SizedBox(
                    width: 46,
                    child: Center(
                        child: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                statusColor?.withValues(alpha: 0.18),
                            foregroundColor: statusColor,
                            child: Text('${index + 1}')))),
                preferenceCell(tableValue(program['program_code']), 88,
                    bold: true),
                SizedBox(
                    width: 240,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 8),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text('${program['program'] ?? '—'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800))),
                                if (program['kktc_national_only'] == true)
                                  const Tooltip(
                                      message: 'KKTC Uyruklu',
                                      child: Icon(Icons.badge_outlined,
                                          size: 18, color: Color(0xff7b4bb7))),
                                if (decision != null)
                                  Tooltip(
                                      message: '${decision['category']}',
                                      child: Icon(decisionIcon(decision),
                                          size: 18, color: statusColor)),
                                if (onDelete != null)
                                  IconButton(
                                      tooltip: 'Listeden çıkar',
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20,
                                          color: Color(0xffa95757)),
                                      onPressed: onDelete)
                              ]),
                              Text(
                                  '${program['university'] ?? '—'} / ${program['city'] ?? '—'}'
                                  '${program['fee_status'] == null ? '' : ' • ${program['fee_status']}'}'
                                  '${program['language'] == null ? '' : ' • ${program['language']}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11))
                            ]))),
                preferenceCell(tableValue(program['score_type']), 58,
                    bold: true, color: scoreTypeColor(program['score_type'])),
                preferenceCell(extraEducation, 82),
                preferenceCell(tableValue(program['duration']), 54),
                preferenceCell(tableValue(program['language']), 78),
                preferenceCell(tableValue(program['fee_status']), 92),
                preferenceCell(tableValue(rankValue(program, 2025)), 86,
                    bold: true),
                preferenceCell(tableValue(rankValue(program, 2024)), 86),
                preferenceCell(
                    tableValue(program['min_score_2025'], decimal: true), 88,
                    bold: true),
                preferenceCell(tableValue(program['quota_2026']), 72),
                preferenceCell(tableValue(program['special_conditions']), 145,
                    maxLines: 4),
                preferenceCell(tableValue(program['accreditation']), 92),
                preferenceCell(kpssDisplay(program['extra']), 76,
                    bold: program['extra'] is Map &&
                        program['extra']['kpss'] != null),
                SizedBox(
                    width: 76,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (reorderable)
                            ReorderableDragStartListener(
                                index: index,
                                child: const Tooltip(
                                    message: 'Sıralamak için sürükle',
                                    child: Icon(Icons.drag_handle)))
                        ]))
              ])),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final basket = ref.watch(preferenceBasketProvider);
    final missingScoreTypes = basket
        .map((program) => '${program['score_type'] ?? ''}')
        .where((type) =>
            rankControllers.containsKey(type) &&
            rankControllers[type]!.text.trim().isEmpty)
        .toSet();
    final categoryCounts = <String, int>{};
    for (final decision in decisions.values) {
      final category = '${decision['category']}';
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(
                    editingListId == null
                        ? 'Tercih Listesi'
                        : 'Tercih Listesi • #$editingListId düzenleniyor',
                    style: Theme.of(context).textTheme.headlineMedium)),
            FilledButton.icon(
                onPressed: saving ? null : save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Kaydediliyor' : 'Taslağı kaydet')),
            if (editingListId != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () => previewPdf(editingListId!),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Hızlı PDF')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () => downloadExport(editingListId!, 'xlsx'),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Excel'))
            ],
            const SizedBox(width: 8),
            OutlinedButton.icon(
                onPressed: studentId == null ? null : showSavedLists,
                icon: const Icon(Icons.history),
                label: const Text('Kayıtlı listeler'))
          ]),
          Align(
              alignment: Alignment.centerRight,
              child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (basket.isNotEmpty)
                      OutlinedButton.icon(
                          onPressed: clearPreferenceList,
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xffa95757),
                              side: const BorderSide(color: Color(0xffe5bcbc))),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Listeyi boşalt')),
                    OutlinedButton.icon(
                        onPressed: clearPreferenceForm,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xffa95757),
                            side: const BorderSide(color: Color(0xffe5bcbc))),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Formu temizle'))
                  ]))),
          const SizedBox(height: 12),
          TextField(
              controller: listName,
              onChanged: (value) =>
                  ref.read(preferenceListNameProvider.notifier).state = value,
              decoration: const InputDecoration(
                  labelText: 'Liste adı',
                  prefixIcon: Icon(Icons.edit_note_outlined))),
          const SizedBox(height: 12),
          FutureBuilder(
              future: students,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  final unauthorized = snapshot.error is DioException &&
                      (snapshot.error as DioException).response?.statusCode ==
                          401;
                  if (unauthorized) {
                    handleExpiredSession();
                    return const Row(children: [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text(
                          'Oturum süresi doldu; giriş ekranına yönlendiriliyor.')
                    ]);
                  }
                  return Row(children: [
                    const Expanded(child: Text('Öğrenci listesi yüklenemedi.')),
                    FilledButton.icon(
                        onPressed: () => setState(() {
                              students =
                                  ref.read(dioProvider).get('/api/students');
                            }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tekrar dene'))
                  ]);
                }
                final studentRows = (snapshot.data?.data as List?) ?? [];
                return Column(children: [
                  DropdownButtonFormField<int>(
                      key: ValueKey(studentId),
                      initialValue: studentId,
                      decoration: const InputDecoration(labelText: 'Öğrenci'),
                      items: studentRows
                          .map<DropdownMenuItem<int>>((x) =>
                              DropdownMenuItem<int>(
                                  value: x['id'],
                                  child: Text(
                                      '${x['first_name']} ${x['last_name']}')))
                          .toList(),
                      onChanged:
                          loadingStudentResults ? null : loadStudentResults),
                  const SizedBox(height: 12),
                  if (loadingStudentResults)
                    const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator()),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final type in const ['TYT', 'SAY', 'EA', 'SÖZ', 'DİL'])
                      SizedBox(
                          width: 170,
                          child: TextField(
                              controller: rankControllers[type],
                              readOnly: true,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: '$type başarı sırası'))),
                    FilledButton.tonalIcon(
                        onPressed: loadingStudentResults ? null : analyze,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Tümünü analiz et'))
                  ])
                ]);
              }),
          const SizedBox(height: 12),
          if (!loadingStudentResults && missingScoreTypes.isNotEmpty)
            Card(
                color: const Color(0xffffe8e8),
                child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.red),
                    title: const Text(
                        'Başarı sıralaması girilmeyen puan türünde program eklenmiştir.'),
                    subtitle: Text(
                        'Eksik puan türleri: ${missingScoreTypes.join(', ')}. Öğrencinin YKS sonuçlarından bu sıralamaları girin.'))),
          if (!loadingStudentResults && missingScoreTypes.isNotEmpty)
            const SizedBox(height: 8),
          const Card(
              color: Color(0xfffff4e5),
              child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'Bu sistem yalnızca karar destek amacıyla hazırlanmıştır. Kesin yerleşme garantisi vermez. Güncel ÖSYM/YÖK kılavuzunu kontrol edin.'))),
          if (categoryCounts.isNotEmpty)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: categoryCounts.entries
                                  .map((x) =>
                                      Chip(label: Text('${x.key}: ${x.value}')))
                                  .toList()),
                          if (categoryCounts.length == 1 &&
                              decisions.length > 1)
                            const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                    '⚠ Listenin tamamı aynı risk grubunda. Daha dengeli bir dağılım değerlendirin.'))
                        ]))),
          Expanded(
              child: basket.isEmpty
                  ? const Center(
                      child: Text(
                          'Program arama ekranından tercih listenize program ekleyin.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: 1382,
                          child: ReorderableListView.builder(
                              buildDefaultDragHandles: false,
                              header: preferenceTableHeader(),
                              itemCount: basket.length,
                              onReorder: (oldIndex, newIndex) {
                                final updated = [...basket];
                                if (newIndex > oldIndex) newIndex--;
                                final item = updated.removeAt(oldIndex);
                                updated.insert(newIndex, item);
                                ref
                                    .read(preferenceBasketProvider.notifier)
                                    .state = updated;
                              },
                              itemBuilder: (_, index) {
                                final p = basket[index];
                                final decision = decisions[p['id']];
                                final statusColor = decisionColor(decision);
                                return preferenceTableRow(
                                    p, index, decision, statusColor, () {
                                  final updated = [...basket]..removeAt(index);
                                  ref
                                      .read(preferenceBasketProvider.notifier)
                                      .state = updated;
                                });
                              }))))
        ]));
  }

  Future<void> showSavedLists() async {
    if (ref.read(tokenProvider) == null) {
      context.go('/giris');
      return;
    }
    final response = await ref.read(dioProvider).get('/api/preference-lists',
        queryParameters: {'student_id': studentId});
    final lists = response.data as List;
    if (!mounted) return;
    await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Kayıtlı tercih listeleri',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (lists.isEmpty)
                const ListTile(title: Text('Henüz kayıtlı liste yok.')),
              ...lists.map((item) => Card(
                  child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text('${item['name']}'),
                      subtitle:
                          Text('Sürüm ${item['version']} • ${item['status']}'),
                      onTap: () => showSavedListDetails(item['id']),
                      trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'version') {
                              await ref.read(dioProvider).post(
                                  '/api/preference-lists/${item['id']}/versions');
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Yeni liste sürümü oluşturuldu.')));
                              }
                            } else if (action == 'delete') {
                              final confirmed = await showDialog<bool>(
                                      context: sheetContext,
                                      builder: (confirmContext) => AlertDialog(
                                              title: const Text(
                                                  'Tercih listesini sil'),
                                              content: Text(
                                                  '${item['name']} kalıcı olarak silinsin mi?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            confirmContext,
                                                            false),
                                                    child:
                                                        const Text('Vazgeç')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            confirmContext,
                                                            true),
                                                    child: const Text('Sil'))
                                              ])) ??
                                  false;
                              if (!confirmed) return;
                              await ref.read(dioProvider).delete(
                                  '/api/preference-lists/${item['id']}');
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (editingListId == item['id']) {
                                setState(() => editingListId = null);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'version',
                                    child: Text('Yeni sürüm oluştur')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Listeyi sil'))
                              ]))))
            ])));
  }

  Future<void> showSavedListDetails(int listId) async {
    final response =
        await ref.read(dioProvider).get('/api/preference-lists/$listId');
    if (!mounted) return;
    final data = response.data as Map;
    final items = data['items'] as List;
    await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text('${data['name']} • Sürüm ${data['version']}'),
                content: SizedBox(
                    width: 1180,
                    height: 560,
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                            width: 1382,
                            child: Column(children: [
                              preferenceTableHeader(),
                              Expanded(
                                  child: ListView.builder(
                                      itemCount: items.length,
                                      itemBuilder: (_, index) {
                                        final item = items[index];
                                        final programData = item['program_data']
                                                is Map
                                            ? Map<String, dynamic>.from(
                                                item['program_data'])
                                            : <String, dynamic>{
                                                'id': item['program_id'],
                                                'program': item['program'],
                                                'university':
                                                    item['university'],
                                                'city': item['city'],
                                                'score_type': item['score_type']
                                              };
                                        final itemDecision = <String, dynamic>{
                                          'category': item['category'],
                                          'explanation': item['explanation']
                                        };
                                        return preferenceTableRow(
                                            programData,
                                            index,
                                            itemDecision,
                                            decisionColor(itemDecision),
                                            null,
                                            reorderable: false);
                                      }))
                            ])))),
                actions: [
                  TextButton.icon(
                      onPressed: () {
                        ref.read(preferenceBasketProvider.notifier).state = [
                          for (final item in items)
                            if (item['program_data'] is Map)
                              Map<String, dynamic>.from(item['program_data'])
                            else
                              <String, dynamic>{
                                'id': item['program_id'],
                                'program': item['program'],
                                'university': item['university'],
                                'city': item['city'],
                                'score_type':
                                    item['score_type'] ?? data['score_type']
                              }
                        ];
                        setState(() {
                          editingListId = listId;
                          studentId = data['student_id'];
                          scoreType = data['score_type'] ?? 'SAY';
                          listName.text = '${data['name']}';
                          decisions = {
                            for (final item in items)
                              item['program_id']: <String, dynamic>{
                                'category': item['category'],
                                'explanation': item['explanation']
                              }
                          };
                        });
                        ref
                            .read(selectedPreferenceStudentProvider.notifier)
                            .state = data['student_id'];
                        ref.read(preferenceListNameProvider.notifier).state =
                            '${data['name']}';
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Liste düzenlemek için çalışma alanına yüklendi.')));
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Düzenlemeye aç')),
                  if (data['status'] != 'completed')
                    TextButton.icon(
                        onPressed: () async {
                          await updateListStatus(listId, 'completed');
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        icon: const Icon(Icons.task_alt),
                        label: const Text('Tamamlandı')),
                  if (data['status'] != 'archived')
                    TextButton.icon(
                        onPressed: () async {
                          await updateListStatus(listId, 'archived');
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Arşivle')),
                  TextButton.icon(
                      onPressed: () => previewPdf(listId),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF önizle')),
                  TextButton.icon(
                      onPressed: () => downloadExport(listId, 'xlsx'),
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Excel')),
                  TextButton.icon(
                      onPressed: () => downloadExport(listId, 'csv'),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('CSV')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Kapat'))
                ]));
  }

  Future<void> updateListStatus(int listId, String status) async {
    try {
      await ref
          .read(dioProvider)
          .put('/api/preference-lists/$listId', data: {'status': status});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Liste durumu güncellendi: $status')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.response?.data['detail'] ?? 'Liste güncellenemedi.')));
      }
    }
  }

  Future<void> downloadExport(int listId, String extension) async {
    try {
      final response = await ref.read(dioProvider).get(
          '/api/preference-lists/$listId/export.$extension',
          options: Options(responseType: ResponseType.bytes));
      final mime = {
        'pdf': 'application/pdf',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'csv': 'text/csv'
      }[extension]!;
      await FileSaver.instance.saveFile(
          name: '2026-yks-tercih-$listId',
          bytes: Uint8List.fromList(List<int>.from(response.data)),
          fileExtension: extension,
          mimeType: MimeType.custom,
          customMimeType: mime);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${extension.toUpperCase()} kaydedildi.')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(dioErrorMessage(e, 'Dosya indirilemedi.'))));
      }
    }
  }

  Future<void> previewPdf(int listId) async {
    try {
      final response = await ref.read(dioProvider).get(
          '/api/preference-lists/$listId/export.pdf',
          options: Options(responseType: ResponseType.bytes));
      final bytes = Uint8List.fromList(List<int>.from(response.data));
      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (dialogContext) => Dialog(
              insetPadding: const EdgeInsets.all(18),
              child: SizedBox(
                  width: 1180,
                  height: 760,
                  child: PdfPreview(
                      build: (_) async => bytes,
                      pdfFileName: '2026-yks-tercih-$listId.pdf',
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false))));
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(dioErrorMessage(e, 'PDF önizlemesi açılamadı.'))));
      }
    }
  }
}

class ComparePage extends ConsumerWidget {
  const ComparePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programs = ref.watch(comparisonProvider);
    if (programs.isEmpty) {
      return const Center(
          child: Text(
              'Program arama ekranından karşılaştırmaya en fazla dört program ekleyin.'));
    }
    final rows = <(String, dynamic Function(Map<String, dynamic>))>[
      ('Üniversite', (p) => p['university']),
      ('Program', (p) => p['program']),
      ('Şehir', (p) => p['city']),
      ('Üniversite türü', (p) => p['university_type']),
      ('Ücret/Burs', (p) => p['fee_status']),
      ('Dil', (p) => p['language']),
      ('Süre', (p) => p['duration']),
      ('Kontenjan', (p) => p['quota_2026']),
      ('2025 sıralama', (p) => p['min_rank_2025'] ?? p['rank_status_2025']),
      ('Akreditasyon', (p) => p['accreditation']),
    ];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(
            child: Text('Program Karşılaştırma',
                style: Theme.of(context).textTheme.headlineMedium)),
        TextButton.icon(
            onPressed: () => ref.read(comparisonProvider.notifier).state = [],
            icon: const Icon(Icons.clear_all),
            label: const Text('Temizle'))
      ]),
      const SizedBox(height: 12),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
              columns: [
                const DataColumn(label: Text('Alan')),
                ...programs.map((p) => DataColumn(
                    label: SizedBox(
                        width: 190,
                        child: Text('${p['program']}',
                            maxLines: 2, overflow: TextOverflow.ellipsis))))
              ],
              rows: rows
                  .map((row) => DataRow(cells: [
                        DataCell(Text(row.$1,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                        ...programs.map((p) => DataCell(SizedBox(
                            width: 190, child: Text('${row.$2(p) ?? '—'}'))))
                      ]))
                  .toList()))
    ]);
  }
}

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tokenProvider) == null) {
      return Center(
          child: FilledButton.icon(
              onPressed: () => context.go('/giris'),
              icon: const Icon(Icons.login),
              label: const Text('Raporlar için giriş yap')));
    }
    return FutureBuilder(
        future: ref.read(dioProvider).get('/api/reports/summary'),
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Rapor verileri alınamadı.'));
          }
          final report = snapshot.data!.data as Map;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('Raporlar', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              StatCard(
                  icon: Icons.people,
                  label: 'Toplam öğrenci',
                  value: '${report['students']}'),
              StatCard(
                  icon: Icons.fact_check,
                  label: 'Listesi olan öğrenci',
                  value: '${report['students_with_lists']}'),
              StatCard(
                  icon: Icons.list_alt,
                  label: 'Tercih listesi',
                  value: '${report['preference_lists']}'),
              StatCard(
                  icon: Icons.school,
                  label: 'Toplam tercih',
                  value: '${report['preference_items']}')
            ]),
            const SizedBox(height: 20),
            _reportTable('En çok tercih edilen üniversiteler',
                report['top_universities'] as List),
            _reportTable('En çok tercih edilen programlar',
                report['top_programs'] as List),
            _reportTable('Puan türü dağılımı', report['score_types'] as List),
            _reportTable(
                'Tercih risk kategorileri', report['categories'] as List)
          ]);
        });
  }

  Widget _reportTable(String title, List rows) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            if (rows.isEmpty) const Text('Henüz veri yok.'),
            ...rows.map((x) => ListTile(
                dense: true,
                title: Text('${x['name']}'),
                trailing: Text('${x['count']}')))
          ])));
}

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  Map<String, dynamic>? report;
  Uint8List? selectedBytes;
  String? selectedName;
  final dataYear = TextEditingController(text: '2027');
  bool loading = false;
  bool importing = false;

  Future<void> pickAndPreview() async {
    if (ref.read(tokenProvider) == null) {
      context.go('/giris');
      return;
    }
    final selection = await picker.FilePicker.pickFiles(
        type: picker.FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true);
    if (selection == null) return;
    final file = selection.files.single;
    if (file.bytes == null) return;
    setState(() {
      loading = true;
      report = null;
      selectedBytes = file.bytes;
      selectedName = file.name;
    });
    try {
      final form = FormData.fromMap(
          {'file': MultipartFile.fromBytes(file.bytes!, filename: file.name)});
      final response =
          await ref.read(dioProvider).post('/api/imports/preview', data: form);
      setState(() => report = Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                e.response?.data['detail'] ?? 'Excel dosyası doğrulanamadı.')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> commitImport() async {
    final year = int.tryParse(dataYear.text);
    if (selectedBytes == null || selectedName == null || year == null) return;
    setState(() => importing = true);
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(selectedBytes!, filename: selectedName!)
      });
      final response = await ref.read(dioProvider).post('/api/imports/commit',
          queryParameters: {'data_year': year}, data: form);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${response.data['record_count']} kayıt aktarıldı; ${response.data['added']} yeni, ${response.data['updated']} güncellendi.')));
        setState(() {
          report = null;
          selectedBytes = null;
          selectedName = null;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.response?.data['detail'] ?? 'İçe aktarma başarısız.')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Text('Excel Veri Aktarımı',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
            'Yeni YKS çalışma kitabını veritabanında değişiklik yapmadan önce doğrulayın. Yalnız yönetici rolü kullanabilir.'),
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
                onPressed: loading ? null : pickAndPreview,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(
                    loading ? 'Dosya inceleniyor' : 'Excel seç ve önizle'))),
        if (report != null) ...[
          const SizedBox(height: 20),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              report!['can_import'] == true
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: report!['can_import'] == true
                                  ? Colors.green
                                  : Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text('${report!['file_name']}',
                                  style:
                                      Theme.of(context).textTheme.titleLarge))
                        ]),
                        const Divider(),
                        Text('tablo3: ${report!['counts']['tablo3']} kayıt'),
                        Text('tablo4: ${report!['counts']['tablo4']} kayıt'),
                        Text('Toplam: ${report!['total']} kayıt'),
                        Text(
                            'Beklenen sayılarla eşleşme: ${report!['matches_expected'] == true ? 'Evet' : 'Hayır'}'),
                        Text(
                            'Yinelenen program kodu: ${(report!['duplicate_codes'] as List).length}'),
                        const SizedBox(height: 8),
                        SelectableText('SHA-256: ${report!['sha256']}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        Text(report!['can_import'] == true
                            ? 'Dosya içe aktarılmaya uygundur. Onaylı aktarım komutu veri sürümü oluşturarak çalıştırılabilir.'
                            : 'Dosya aktarım için uygun değildir; veritabanında değişiklik yapılmadı.'),
                        if (report!['can_import'] == true) ...[
                          const SizedBox(height: 16),
                          Row(children: [
                            SizedBox(
                                width: 140,
                                child: TextField(
                                    controller: dataYear,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Veri yılı'))),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                                onPressed: importing ? null : commitImport,
                                icon: importing
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.cloud_upload),
                                label: Text(importing
                                    ? 'Aktarılıyor'
                                    : 'Aktarımı onayla'))
                          ]),
                          const SizedBox(height: 8),
                          const Text(
                              'Onay sonrasında yeni veri sürümü aktif olur. Aynı dosya hash değeri ikinci kez kabul edilmez.',
                              style: TextStyle(fontSize: 12))
                        ]
                      ])))
        ],
        const SizedBox(height: 20),
        FutureBuilder(
            future: ref.watch(tokenProvider) == null
                ? null
                : ref.read(dioProvider).get('/api/imports'),
            builder: (_, snapshot) {
              final rows = (snapshot.data?.data as List?) ?? [];
              return Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Veri sürümü geçmişi',
                                style: Theme.of(context).textTheme.titleLarge),
                            const Divider(),
                            if (rows.isEmpty)
                              const Text('Henüz görüntülenecek sürüm yok.'),
                            ...rows.map((x) => ListTile(
                                leading: Icon(
                                    x['is_active'] == true
                                        ? Icons.check_circle
                                        : Icons.history,
                                    color: x['is_active'] == true
                                        ? Colors.green
                                        : null),
                                title: Text(
                                    '${x['data_year']} • ${x['file_name']}'),
                                subtitle: Text(
                                    '${x['record_count']} kayıt\n${x['file_hash']}'),
                                isThreeLine: true))
                          ])));
            })
      ]);
}

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});
  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  late Future<Response> users;
  @override
  void initState() {
    super.initState();
    users = ref.read(dioProvider).get('/api/users');
  }

  void refresh() =>
      setState(() => users = ref.read(dioProvider).get('/api/users'));

  Future<void> createUser() async {
    final email = TextEditingController();
    final name = TextEditingController();
    final password = TextEditingController();
    String role = 'viewer';
    await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
                    title: const Text('Yeni kullanıcı'),
                    content: SizedBox(
                        width: 440,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(
                              controller: name,
                              decoration:
                                  const InputDecoration(labelText: 'Ad soyad')),
                          TextField(
                              controller: email,
                              decoration:
                                  const InputDecoration(labelText: 'E-posta')),
                          TextField(
                              controller: password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Şifre (en az 10 karakter)')),
                          DropdownButtonFormField<String>(
                              initialValue: role,
                              decoration:
                                  const InputDecoration(labelText: 'Rol'),
                              items: const {
                                'admin': 'Yönetici',
                                'counselor': 'Rehber öğretmen',
                                'teacher': 'Öğretmen',
                                'viewer': 'Görüntüleyici'
                              }
                                  .entries
                                  .map((x) => DropdownMenuItem(
                                      value: x.key, child: Text(x.value)))
                                  .toList(),
                              onChanged: (value) =>
                                  setDialogState(() => role = value!))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Vazgeç')),
                      FilledButton(
                          onPressed: () async {
                            try {
                              await ref
                                  .read(dioProvider)
                                  .post('/api/users', data: {
                                'email': email.text,
                                'full_name': name.text,
                                'password': password.text,
                                'role': role
                              });
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              refresh();
                            } on DioException catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            e.response?.data['detail'] ??
                                                'Kullanıcı oluşturulamadı.')));
                              }
                            }
                          },
                          child: const Text('Oluştur'))
                    ])));
  }

  Future<void> updateUser(int id, {String? role, bool? isActive}) async {
    try {
      await ref.read(dioProvider).patch('/api/users/$id',
          data: {'role': role, 'is_active': isActive}
            ..removeWhere((_, value) => value == null));
      refresh();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                e.response?.data['detail'] ?? 'Kullanıcı güncellenemedi.')));
      }
    }
  }

  Future<void> editUser(Map user) async {
    final name =
        TextEditingController(text: '${user['full_name'] ?? ''}'.trim());
    final password = TextEditingController();
    final passwordAgain = TextEditingController();
    String role = '${user['role']}';
    bool isActive = user['is_active'] == true;
    bool hidePassword = true;
    String? error;

    await showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
                    title: const Text('Kullanıcıyı düzenle'),
                    content: SizedBox(
                        width: 460,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: TextEditingController(
                                      text: '${user['email']}'),
                                  readOnly: true,
                                  decoration: const InputDecoration(
                                      labelText: 'E-posta')),
                              TextField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText: 'Ad soyad')),
                              DropdownButtonFormField<String>(
                                  initialValue: role,
                                  decoration:
                                      const InputDecoration(labelText: 'Rol'),
                                  items: const {
                                    'admin': 'Yönetici',
                                    'counselor': 'Rehber öğretmen',
                                    'teacher': 'Öğretmen',
                                    'viewer': 'Görüntüleyici'
                                  }
                                      .entries
                                      .map((x) => DropdownMenuItem(
                                          value: x.key, child: Text(x.value)))
                                      .toList(),
                                  onChanged: (value) => setDialogState(
                                      () => role = value ?? role)),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Kullanıcı aktif'),
                                  value: isActive,
                                  onChanged: (value) =>
                                      setDialogState(() => isActive = value)),
                              TextField(
                                  controller: password,
                                  obscureText: hidePassword,
                                  decoration: InputDecoration(
                                      labelText:
                                          'Yeni şifre (değişmeyecekse boş bırakın)',
                                      helperText: 'En az 10 karakter',
                                      suffixIcon: IconButton(
                                          tooltip: hidePassword
                                              ? 'Şifreyi göster'
                                              : 'Şifreyi gizle',
                                          onPressed: () => setDialogState(() =>
                                              hidePassword = !hidePassword),
                                          icon: Icon(hidePassword
                                              ? Icons.visibility
                                              : Icons.visibility_off)))),
                              TextField(
                                  controller: passwordAgain,
                                  obscureText: hidePassword,
                                  decoration: const InputDecoration(
                                      labelText: 'Yeni şifre tekrar')),
                              if (error != null) ...[
                                const SizedBox(height: 12),
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)))
                              ]
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Vazgeç')),
                      FilledButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('Kaydet'),
                          onPressed: () async {
                            final newPassword = password.text;
                            if (name.text.trim().isEmpty) {
                              setDialogState(
                                  () => error = 'Ad soyad boş bırakılamaz.');
                              return;
                            }
                            if (newPassword.isNotEmpty &&
                                newPassword.length < 10) {
                              setDialogState(() =>
                                  error = 'Şifre en az 10 karakter olmalıdır.');
                              return;
                            }
                            if (newPassword != passwordAgain.text) {
                              setDialogState(() =>
                                  error = 'Şifreler birbiriyle eşleşmiyor.');
                              return;
                            }
                            try {
                              final data = <String, dynamic>{
                                'full_name': name.text.trim(),
                                'role': role,
                                'is_active': isActive,
                              };
                              if (newPassword.isNotEmpty) {
                                data['password'] = newPassword;
                              }
                              await ref.read(dioProvider).patch(
                                  '/api/users/${user['id']}',
                                  data: data);
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              refresh();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Kullanıcı güncellendi.')));
                              }
                            } on DioException catch (e) {
                              setDialogState(() => error =
                                  e.response?.data['detail']?.toString() ??
                                      'Kullanıcı güncellenemedi.');
                            }
                          })
                    ])));
    name.dispose();
    password.dispose();
    passwordAgain.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(tokenProvider) == null) {
      return Center(
          child: FilledButton.icon(
              onPressed: () => context.go('/giris'),
              icon: const Icon(Icons.login),
              label: const Text('Kullanıcı yönetimi için giriş yap')));
    }
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text('Kullanıcı ve Rol Yönetimi',
                    style: Theme.of(context).textTheme.headlineMedium)),
            FilledButton.icon(
                onPressed: createUser,
                icon: const Icon(Icons.person_add),
                label: const Text('Kullanıcı ekle'))
          ]),
          const SizedBox(height: 12),
          Expanded(
              child: FutureBuilder<Response>(
                  future: users,
                  builder: (_, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                          child: Text(
                              'Bu ekran yalnızca yöneticiler tarafından kullanılabilir.'));
                    }
                    final rows = snapshot.data!.data as List;
                    return ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, index) {
                          final user = rows[index];
                          return Card(
                              child: ListTile(
                                  leading: CircleAvatar(
                                      child: Text('${user['full_name']}'
                                          .substring(0, 1))),
                                  title: Text('${user['full_name']}'),
                                  subtitle: Text('${user['email']}'),
                                  trailing: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        IconButton(
                                            tooltip: 'Kullanıcıyı düzenle',
                                            onPressed: () => editUser(user),
                                            icon: const Icon(Icons.edit)),
                                        SizedBox(
                                            width: 180,
                                            child:
                                                DropdownButtonFormField<String>(
                                                    initialValue: user['role'],
                                                    items: const {
                                                      'admin': 'Yönetici',
                                                      'counselor':
                                                          'Rehber öğretmen',
                                                      'teacher': 'Öğretmen',
                                                      'viewer': 'Görüntüleyici'
                                                    }
                                                        .entries
                                                        .map((x) =>
                                                            DropdownMenuItem(
                                                                value: x.key,
                                                                child: Text(
                                                                    x.value)))
                                                        .toList(),
                                                    onChanged: (value) =>
                                                        updateUser(user['id'],
                                                            role: value))),
                                        Switch(
                                            value: user['is_active'],
                                            onChanged: (value) => updateUser(
                                                user['id'],
                                                isActive: value))
                                      ])));
                        });
                  }))
        ]));
  }
}

class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tokenProvider) == null) {
      return Center(
          child: FilledButton.icon(
              onPressed: () => context.go('/giris'),
              icon: const Icon(Icons.login),
              label: const Text('Denetim kayıtları için giriş yap')));
    }
    return FutureBuilder(
        future: ref.read(dioProvider).get('/api/audit-logs'),
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text(
                    'Bu ekran yalnızca yöneticiler tarafından kullanılabilir.'));
          }
          final data = snapshot.data!.data as Map;
          final rows = data['items'] as List;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('Denetim Kayıtları',
                style: Theme.of(context).textTheme.headlineMedium),
            Text('${data['total']} işlem kaydı'),
            const SizedBox(height: 12),
            ...rows.map((item) => Card(
                child: ListTile(
                    leading: const Icon(Icons.manage_search),
                    title: Text('${item['action']}'),
                    subtitle: Text(
                        '${item['user']} • ${item['entity_type']} #${item['entity_id'] ?? '—'}\n${item['created_at']}'),
                    isThreeLine: true,
                    trailing: Tooltip(
                        message: '${item['details']}',
                        child: const Icon(Icons.info_outline)))))
          ]);
        });
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final highTarget = TextEditingController();
  final target = TextEditingController();
  final balanced = TextEditingController();
  final updateManifestUrl = TextEditingController();
  bool automaticUpdateCheck = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    if (ref.read(tokenProvider) == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final response = await ref
          .read(dioProvider)
          .get('/api/settings/recommendation-thresholds');
      highTarget.text =
          ((response.data['high_target'] as num) * 100).toStringAsFixed(0);
      target.text = ((response.data['target'] as num) * 100).toStringAsFixed(0);
      balanced.text =
          ((response.data['balanced'] as num) * 100).toStringAsFixed(0);
      final updateResponse =
          await ref.read(dioProvider).get('/api/settings/update');
      updateManifestUrl.text = '${updateResponse.data['manifest_url'] ?? ''}';
      automaticUpdateCheck =
          updateResponse.data['automatic_check'] as bool? ?? true;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    highTarget.dispose();
    target.dispose();
    balanced.dispose();
    updateManifestUrl.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final high = double.tryParse(highTarget.text);
    final middle = double.tryParse(target.text);
    final safe = double.tryParse(balanced.text);
    if (high == null || middle == null || safe == null) return;
    try {
      await ref.read(dioProvider).put('/api/settings/recommendation-thresholds',
          data: {
            'high_target': high / 100,
            'target': middle / 100,
            'balanced': safe / 100
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Öneri eşikleri güncellendi.')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.response?.data['detail'] ?? 'Ayarlar kaydedilemedi.')));
      }
    }
  }

  Future<void> saveUpdateSettings() async {
    try {
      await ref.read(dioProvider).put('/api/settings/update', data: {
        'manifest_url': updateManifestUrl.text.trim(),
        'automatic_check': automaticUpdateCheck,
      });
      updateCheckStarted = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Uzaktan güncelleme ayarları kaydedildi.')));
      }
    } on DioException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.response?.data['detail']?.toString() ??
                'Güncelleme ayarları kaydedilemedi.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(tokenProvider) == null) {
      return Center(
          child: FilledButton.icon(
              onPressed: () => context.go('/giris'),
              icon: const Icon(Icons.login),
              label: const Text('Sistem ayarları için giriş yap')));
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Sistem Ayarları',
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text(
          'Öğrenci sırasına göre göreli program sırası farkı eşiklerini yönetin. Değerler yüzde olarak küçükten büyüğe sıralanmalıdır.'),
      const SizedBox(height: 20),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(spacing: 16, runSpacing: 16, children: [
                _percentField(highTarget, 'Yüksek hedef üst sınırı'),
                _percentField(target, 'Hedef aralığı üst sınırı'),
                _percentField(balanced, 'Dengeli üst sınırı'),
                FilledButton.icon(
                    onPressed: save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Ayarları kaydet'))
              ]))),
      const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Örnek: -20, program sıralamasının öğrenciden en az %20 daha iyi olduğu durumları yüksek hedef olarak sınıflandırır. Küçük başarı sırası daha iyidir.'))),
      const SizedBox(height: 20),
      Card(
          color: const Color(0xffe4f3ef),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Uzaktan Güncelleme',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text(
                        'Yayın manifestinin HTTPS adresini girin. Uygulama paket sürümünü ve SHA-256 değerini bu dosyadan doğrular.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: updateManifestUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Güncelleme manifest adresi',
                            hintText: 'https://sunucunuz.com/yks/latest.json',
                            prefixIcon: Icon(Icons.link))),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Uygulama açılırken güncellemeleri kontrol et'),
                        subtitle: const Text(
                            'Kurulum kullanıcı onayı olmadan başlamaz.'),
                        value: automaticUpdateCheck,
                        onChanged: (value) =>
                            setState(() => automaticUpdateCheck = value)),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: saveUpdateSettings,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Güncelleme ayarını kaydet')),
                      OutlinedButton.icon(
                          onPressed: () =>
                              checkForAppUpdate(context, ref, silent: false),
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Şimdi kontrol et'))
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                        'Güncelleme sırasında öğrenci veritabanı yedeklenir. Başarısız kurulumda önceki uygulama dosyaları geri yüklenir.',
                        style: TextStyle(fontSize: 12))
                  ])))
    ]);
  }

  Widget _percentField(TextEditingController controller, String label) =>
      SizedBox(
          width: 220,
          child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: label, suffixText: '%')));
}
