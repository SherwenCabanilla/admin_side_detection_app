import 'package:flutter/material.dart';
import '../models/admin_user.dart';
import 'admin_dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class AdminLogin extends StatefulWidget {
  const AdminLogin({Key? key}) : super(key: key);

  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  // Set to true during testing to show "Create Admin Account" option on login screen.
  // Set to false in production to hide it.
  static const bool _allowAdminCreation = false;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController.text = ''; // Premade for dev
    _passwordController.text = ''; // Premade for dev
    _initializeFirebase();

    // Auto-focus on email field after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized successfully');
    } catch (e) {
      // Firebase may already be initialized
      debugPrint('Firebase initialization: $e');
      // If it's not an "already initialized" error, show a warning
      if (!e.toString().toLowerCase().contains('already')) {
        debugPrint('⚠️ Firebase initialization error: $e');
      }
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Verify Firebase is initialized before attempting login
      try {
        // Check if Firebase Auth is available (will throw if not initialized)
        FirebaseAuth.instance;
        debugPrint('Firebase Auth instance available');
      } catch (e) {
        debugPrint('Firebase Auth not available: $e');
        setState(() {
          _errorMessage =
              'System is not ready. Please refresh the page and try again.';
          _isLoading = false;
        });
        return;
      }

      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
        String uid = userCredential.user!.uid;
        debugPrint('Checking admin document for UID: $uid');
        DocumentSnapshot adminDoc =
            await FirebaseFirestore.instance
                .collection('admins')
                .doc(uid)
                .get();
        debugPrint('Admin document exists: ${adminDoc.exists}');
        if (adminDoc.exists) {
          final adminUser = AdminUser(
            id: adminDoc['adminID'] ?? uid,
            username: adminDoc['adminName'] ?? '',
            email: adminDoc['email'] ?? _emailController.text.trim(),
            role: 'admin',
            lastLogin: DateTime.now(),
          );

          // Log successful admin login BEFORE navigation
          await FirebaseFirestore.instance.collection('activities').add({
            'action': 'Admin logged in',
            'user':
                adminUser.username.isNotEmpty ? adminUser.username : 'Admin',
            'type': 'login',
            'color': Colors.green.value,
            'icon': Icons.login_rounded.codePoint,
            'timestamp': FieldValue.serverTimestamp(),
          });

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdminDashboardWrapper(adminUser: adminUser),
            ),
          );
        } else {
          // Sign out the user since they're not an admin
          await FirebaseAuth.instance.signOut();
          setState(() {
            _errorMessage =
                'You are not registered as an admin. Please contact the developer at mangosense.app@gmail.com.';
            _isLoading = false;
          });
        }
      } on FirebaseAuthException catch (e) {
        String errorMsg;
        debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
        switch (e.code) {
          case 'user-not-found':
            errorMsg = 'No account found with this email address.';
            break;
          case 'wrong-password':
            errorMsg = 'Incorrect password. Please try again.';
            break;
          case 'invalid-email':
            errorMsg = 'Please enter a valid email address.';
            break;
          case 'user-disabled':
            errorMsg = 'This account has been disabled.';
            break;
          case 'too-many-requests':
            errorMsg =
                'Too many failed login attempts. Please try again in a few minutes.';
            break;
          case 'invalid-credential':
            errorMsg =
                'Invalid email or password.\n\n'
                'Please verify:\n'
                '• Email address is correct\n'
                '• Password is correct\n\n'
                'If you continue having issues, use "Forgot Password" or contact the developer at mangosense.app@gmail.com.';
            break;
          case 'network-request-failed':
            errorMsg = 'Network error. Please check your connection.';
            break;
          case 'operation-not-allowed':
            errorMsg =
                'Login is currently not available. Please contact the developer at mangosense.app@gmail.com.';
            break;
          case 'invalid-api-key':
            errorMsg =
                'Something went wrong with the system configuration. Please contact the developer at mangosense.app@gmail.com.';
            break;
          default:
            // Check if the error message contains 400 or bad request
            if (e.message?.toLowerCase().contains('400') == true ||
                e.message?.toLowerCase().contains('bad request') == true) {
              errorMsg =
                  'Something went wrong. Please contact the developer at mangosense.app@gmail.com.';
            } else {
              errorMsg = e.message ?? 'Login failed. Please try again.';
            }
        }
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      } catch (e) {
        // Log the error for debugging
        debugPrint('Login error: $e');
        String errorString = e.toString().toLowerCase();
        String errorMsg;

        // Check for 400 Bad Request errors
        if (errorString.contains('400') ||
            errorString.contains('bad request')) {
          errorMsg =
              'Something went wrong. Please contact the developer at mangosense.app@gmail.com.';
        } else {
          errorMsg = 'An unexpected error occurred. Please try again.';
        }

        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email to reset password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First check if email exists in Firestore admins collection
      final query =
          await FirebaseFirestore.instance
              .collection('admins')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'This email is not registered as an admin.';
          _isLoading = false;
        });
        return;
      }

      // Check if user exists in Firebase Auth by trying to fetch sign-in methods
      // Note: Firebase doesn't allow checking if user exists directly for security,
      // but we can try to send the reset email and handle errors
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: email,
          actionCodeSettings: ActionCodeSettings(
            url: Uri.base.origin,
            handleCodeInApp: false,
          ),
        );

        debugPrint('Password reset email sent successfully to: $email');

        setState(() {
          _isLoading = false;
        });

        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Password Reset'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A password reset link has been sent to:'),
                    const SizedBox(height: 8),
                    Text(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please check your inbox (and spam folder) for the reset link.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Note: If you don\'t receive the email, please contact the developer at mangosense.app@gmail.com.',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      } on FirebaseAuthException catch (authError) {
        debugPrint(
          'Firebase Auth error during password reset: ${authError.code} - ${authError.message}',
        );
        String errorMsg;

        switch (authError.code) {
          case 'user-not-found':
            errorMsg =
                'No account found for this email. '
                'Please contact the developer at mangosense.app@gmail.com.';
            break;
          case 'invalid-email':
            errorMsg = 'Invalid email address format.';
            break;
          case 'too-many-requests':
            errorMsg =
                'Too many password reset attempts. Please wait a few minutes and try again.';
            break;
          default:
            errorMsg =
                authError.message ??
                'Failed to send reset email. Error: ${authError.code}';
        }

        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Unexpected error in password reset: $e');
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateAdminDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isCreating = false;
    bool obscurePass = true;
    bool obscureConfirm = true;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.person_add,
                    color: const Color.fromARGB(255, 42, 157, 50),
                  ),
                  const SizedBox(width: 8),
                  const Text('Create Admin Account'),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Create a new admin account to access the dashboard.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Admin Name',
                          prefixIcon: const Icon(Icons.person, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter admin name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePass,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscurePass = !obscurePass;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscureConfirm = !obscureConfirm;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade700,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dialogError!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isCreating
                          ? null
                          : () {
                            Navigator.of(context).pop();
                          },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      isCreating
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;

                            setDialogState(() {
                              isCreating = true;
                              dialogError = null;
                            });

                            try {
                              // Save values before any async Firebase calls, because
                              // createUserWithEmailAndPassword auto-signs-in the user,
                              // which triggers AuthWrapper and may dispose the login page.
                              final String savedEmail =
                                  emailController.text.trim();
                              final String savedPassword =
                                  passwordController.text.trim();
                              final String savedName =
                                  nameController.text.trim();

                              // Step 1: Create user in Firebase Authentication
                              final UserCredential userCredential =
                                  await FirebaseAuth.instance
                                      .createUserWithEmailAndPassword(
                                        email: savedEmail,
                                        password: savedPassword,
                                      );

                              final String uid = userCredential.user!.uid;
                              debugPrint(
                                '✅ Firebase Auth account created with UID: $uid',
                              );

                              // Step 2: Sign out IMMEDIATELY to prevent AuthWrapper from
                              // navigating away and disposing the login page
                              await FirebaseAuth.instance.signOut();
                              debugPrint(
                                '✅ Signed out newly created user to prevent auto-navigation',
                              );

                              // Step 3: Create admin document in Firestore (doesn't need auth)
                              await FirebaseFirestore.instance
                                  .collection('admins')
                                  .doc(uid)
                                  .set({
                                    'adminID': uid,
                                    'adminName': savedName,
                                    'email': savedEmail,
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });

                              debugPrint(
                                '✅ Firestore admin document created for UID: $uid',
                              );

                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }

                              // Pre-fill the email in the login form for convenience
                              if (mounted) {
                                _emailController.text = savedEmail;
                                _passwordController.text = '';

                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Admin account created successfully! You can now log in with your email and password.',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: const Color.fromARGB(
                                      255,
                                      42,
                                      157,
                                      50,
                                    ),
                                    duration: const Duration(seconds: 5),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } on FirebaseAuthException catch (e) {
                              debugPrint(
                                'FirebaseAuthException during account creation: ${e.code} - ${e.message}',
                              );
                              String errorMsg;
                              switch (e.code) {
                                case 'email-already-in-use':
                                  errorMsg =
                                      'An account with this email already exists.';
                                  break;
                                case 'invalid-email':
                                  errorMsg = 'Invalid email address.';
                                  break;
                                case 'weak-password':
                                  errorMsg =
                                      'Password is too weak. Please use a stronger password.';
                                  break;
                                case 'operation-not-allowed':
                                  errorMsg =
                                      'Account creation is currently not available. Please contact the developer at mangosense.app@gmail.com.';
                                  break;
                                default:
                                  errorMsg =
                                      e.message ??
                                      'Failed to create account: ${e.code}';
                              }
                              setDialogState(() {
                                dialogError = errorMsg;
                                isCreating = false;
                              });
                            } catch (e) {
                              debugPrint('Error creating admin account: $e');
                              setDialogState(() {
                                dialogError =
                                    'An unexpected error occurred. Please try again.';
                                isCreating = false;
                              });
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 42, 157, 50),
                  ),
                  child:
                      isCreating
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text(
                            'Create Account',
                            style: TextStyle(color: Colors.white),
                          ),
                ),
              ],
            );
          },
        );
      },
    );

    // Note: Do NOT manually dispose dialog controllers here.
    // The dialog may still be animating out when showDialog returns.
    // Local controllers will be garbage collected safely.
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Responsive sizing optimized for 1366x768
    final isSmallScreen = screenWidth < 600;
    final isMediumScreen = screenWidth >= 600 && screenWidth < 1200;
    final isLargeScreen = screenWidth >= 1200;
    final is1366x768 = screenWidth == 1366 && screenHeight == 768;

    // Adjusted dimensions to fit 1366x768 without scrolling
    final cardWidth =
        is1366x768
            ? screenWidth *
                0.28 // Smaller card for 1366x768
            : isSmallScreen
            ? screenWidth * 0.85
            : isMediumScreen
            ? screenWidth * 0.55
            : screenWidth * 0.35;

    final cardMaxWidth =
        is1366x768
            ? 380.0
            : isLargeScreen
            ? 450.0
            : cardWidth;
    final cardMinWidth =
        is1366x768
            ? 340.0
            : isSmallScreen
            ? 300.0
            : 360.0;

    final padding =
        is1366x768
            ? 8.0
            : isSmallScreen
            ? 12.0
            : isMediumScreen
            ? 20.0
            : 28.0;
    final iconSize =
        is1366x768
            ? 30.0
            : isSmallScreen
            ? 40.0
            : isMediumScreen
            ? 50.0
            : 60.0;
    final titleFontSize =
        is1366x768
            ? 16.0
            : isSmallScreen
            ? 20.0
            : isMediumScreen
            ? 24.0
            : 28.0;
    final welcomeFontSize =
        is1366x768
            ? 18.0
            : isSmallScreen
            ? 24.0
            : isMediumScreen
            ? 28.0
            : 32.0;
    final subtitleFontSize =
        is1366x768
            ? 10.0
            : isSmallScreen
            ? 12.0
            : isMediumScreen
            ? 14.0
            : 16.0;
    final buttonHeight =
        is1366x768
            ? 32.0
            : isSmallScreen
            ? 45.0
            : 50.0;
    final inputHeight =
        is1366x768
            ? 32.0
            : isSmallScreen
            ? 45.0
            : 50.0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bgg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color.fromARGB(255, 42, 157, 50).withOpacity(0.7),
                const Color.fromARGB(255, 34, 139, 34).withOpacity(0.7),
                const Color.fromARGB(255, 25, 111, 61).withOpacity(0.7),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                // Added to ensure content fits
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: cardMaxWidth,
                    minWidth: cardMinWidth,
                  ),
                  child: Card(
                    elevation: 10,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        is1366x768 ? padding * 0.4 : padding,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Admin Icon and Title
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color.fromARGB(255, 42, 157, 50),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: EdgeInsets.all(padding * 0.2),
                              child: Icon(
                                Icons.admin_panel_settings,
                                size: iconSize,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: padding * 0.2),
                            Text(
                              'Admin Portal',
                              style: TextStyle(
                                color: const Color.fromARGB(255, 42, 157, 50),
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height:
                                  is1366x768 ? padding * 0.1 : padding * 1.5,
                            ),
                            // Welcome Text
                            Text(
                              'Welcome Back!',
                              style: TextStyle(
                                color: const Color.fromARGB(255, 42, 157, 50),
                                fontSize: welcomeFontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Log in to admin dashboard',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: subtitleFontSize,
                              ),
                            ),
                            SizedBox(
                              height:
                                  is1366x768 ? padding * 0.2 : padding * 1.5,
                            ),
                            // Email Field
                            SizedBox(
                              height: inputHeight,
                              child: TextFormField(
                                controller: _emailController,
                                focusNode: _emailFocusNode,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (value) {
                                  // Move focus to password field when Enter is pressed
                                  _passwordFocusNode.requestFocus();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                      width: 1.0,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                      color: Color.fromARGB(255, 42, 157, 50),
                                      width: 1.5,
                                    ),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.email,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            SizedBox(
                              height:
                                  is1366x768 ? padding * 0.2 : padding * 0.5,
                            ),
                            // Password Field
                            SizedBox(
                              height: inputHeight,
                              child: TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocusNode,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (value) {
                                  // Submit the form when Enter is pressed in password field
                                  if (!_isLoading) {
                                    _login();
                                  }
                                },
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                      width: 1.0,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: const BorderSide(
                                      color: Color.fromARGB(255, 42, 157, 50),
                                      width: 1.5,
                                    ),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            // Forgot Password Link
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed:
                                    _isLoading ? null : _sendPasswordResetEmail,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: const Color.fromARGB(
                                      255,
                                      42,
                                      157,
                                      50,
                                    ),
                                    fontSize: subtitleFontSize * 0.85,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              SizedBox(height: padding * 0.1),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFFFAB91),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                            SizedBox(
                              height:
                                  is1366x768 ? padding * 0.2 : padding * 1.0,
                            ),
                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(
                                    255,
                                    42,
                                    157,
                                    50,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  elevation: 5,
                                ),
                                child:
                                    _isLoading
                                        ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                        : Text(
                                          'Log in',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: subtitleFontSize,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                              ),
                            ),
                            // Create Admin Account - only visible when _allowAdminCreation is true
                            if (_allowAdminCreation) ...[
                              SizedBox(
                                height:
                                    is1366x768 ? padding * 0.3 : padding * 0.5,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'No admin account? ',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: subtitleFontSize * 0.85,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _isLoading
                                            ? null
                                            : _showCreateAdminDialog,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Create Admin Account',
                                      style: TextStyle(
                                        color: const Color.fromARGB(
                                          255,
                                          42,
                                          157,
                                          50,
                                        ),
                                        fontSize: subtitleFontSize * 0.85,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }
}
