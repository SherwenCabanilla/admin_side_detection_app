import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/admin_login.dart';
import 'screens/admin_dashboard.dart';
import 'models/admin_user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if Firebase is already initialized
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // If Firebase is already initialized, just continue
    debugPrint('Firebase already initialized: $e');
  }

  if (kReleaseMode) {
    // Disable debugPrint in release to avoid any logging overhead
    debugPrint = (String? message, {int? wrapWidth}) {};
    runZonedGuarded(
      () {
        runApp(const MyApp());
      },
      (error, stackTrace) {
        // Optionally send errors to crash reporting in release
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) {
          // Suppress prints in release builds
        },
      ),
    );
  } else {
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin Web',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          // User is signed in, check if they are an admin
          return FutureBuilder<DocumentSnapshot>(
            future:
                FirebaseFirestore.instance
                    .collection('admins')
                    .doc(snapshot.data!.uid)
                    .get(),
            builder: (context, adminSnapshot) {
              if (adminSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (adminSnapshot.hasData && adminSnapshot.data!.exists) {
                // User is an admin, create admin user object and show dashboard
                final adminData =
                    adminSnapshot.data!.data() as Map<String, dynamic>;
                final adminUser = AdminUser(
                  id: adminData['adminID'] ?? snapshot.data!.uid,
                  username: adminData['adminName'] ?? '',
                  email: adminData['email'] ?? snapshot.data!.email ?? '',
                  role: 'admin',
                  lastLogin: DateTime.now(),
                );
                return AdminDashboardWrapper(adminUser: adminUser);
              } else {
                // User is signed in but not an admin, sign them out
                FirebaseAuth.instance.signOut();
                return const AdminLogin();
              }
            },
          );
        }

        // User is not signed in, show login screen
        return const AdminLogin();
      },
    );
  }
}
// flutter build web --release --dart-define=FLUTTER_WEB_USE_SKIA=true
//flutter run -d chrome --profile --dart-define=FLUTTER_WEB_USE_SKIA=true