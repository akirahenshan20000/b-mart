import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/network/api_client.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/service_selection_screen.dart';
import '../features/customer/customer_shell.dart';
import '../features/driver/driver_shell.dart';

class BersolekMartApp extends ConsumerWidget {
  const BersolekMartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Session?>>(authControllerProvider, (previous, next) {
      if (previous is AsyncData<Session?> &&
          previous.value != null &&
          next is AsyncData<Session?> &&
          next.value == null) {
        // A completed logout returns the user to the normal service chooser.
        ref.read(selectedServiceProvider.notifier).select(null);
      }
    });

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
        dividerColor: const Color(0xFFECE1E3),
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
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD20A2E),
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            minimumSize: const Size(48, 48),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      // Keep the login form mounted during an API request. A full-screen
      // splash is reserved for the initial session restore, not button loading.
      home: auth.isLoading &&
              (selectedService == 'customer' || selectedService == 'driver')
          ? LoginScreen(expectedRole: selectedService)
          : auth.when(
        loading: () => const _Splash(),
        error: (error, _) {
          if (selectedService == 'choose') return const ServiceSelectionScreen();
          if (selectedService == 'customer' || selectedService == 'driver') {
            return LoginScreen(
              message: apiErrorMessage(error),
              expectedRole: selectedService,
            );
          }
          return _SessionRestoreError(
            message: apiErrorMessage(error),
            onRetry: () => ref.invalidate(authControllerProvider),
            onSignOut: () async {
              await ref.read(authControllerProvider.notifier).logout();
            },
          );
        },
        data: (session) {
          if (session == null) {
            if (selectedService == 'choose') return const ServiceSelectionScreen();
            if (selectedService == 'customer' || selectedService == 'driver') {
              return LoginScreen(expectedRole: selectedService);
            }
            return const WelcomeSplashScreen();
          }
          return session.isDriver ? const DriverShell() : const CustomerShell();
        },
      ),
    );
  }
}

class _SessionRestoreError extends StatelessWidget {
  const _SessionRestoreError({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFFD20A2E)),
                    const SizedBox(height: 16),
                    const Text(
                      'Sesi belum dapat diperiksa',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Coba lagi'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () { onSignOut(); },
                        child: const Text('Keluar dan masuk ulang'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
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
