import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/service_selection_screen.dart';
import '../features/customer/customer_shell.dart';
import '../features/driver/driver_shell.dart';

class BersolekMartApp extends ConsumerWidget {
  const BersolekMartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final selectedService = ref.watch(selectedServiceProvider);

    return MaterialApp(
      title: 'BersolekMart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD20A2E),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFD20A2E),
          onPrimary: Colors.white,
          secondary: const Color(0xFF171717),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4F4),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFF171113),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF171113),
          indicatorColor: const Color(0xFFD20A2E),
          labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            TextStyle(
              color: states.contains(WidgetState.selected) ? Colors.white : Colors.white70,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            )),
          iconTheme: WidgetStateProperty.resolveWith((states) =>
            IconThemeData(color: states.contains(WidgetState.selected) ? Colors.white : Colors.white70)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: const Color(0xFFFFF8F8),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: auth.when(
        loading: () => const _Splash(),
        error: (error, _) => LoginScreen(message: '$error', expectedRole: selectedService),
        data: (session) {
          if (session == null) return const WelcomeSplashScreen();
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
