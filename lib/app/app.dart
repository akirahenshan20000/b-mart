import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/customer/customer_shell.dart';
import '../features/driver/driver_shell.dart';

class BersolekMartApp extends ConsumerWidget {
  const BersolekMartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return MaterialApp(
      title: 'BersolekMart',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E8B6D)),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      home: auth.when(
        loading: () => const _Splash(),
        error: (error, _) => LoginScreen(message: '$error'),
        data: (session) {
          if (session == null) return const LoginScreen();
          return session.isDriver ? const DriverShell() : const CustomerShell();
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
