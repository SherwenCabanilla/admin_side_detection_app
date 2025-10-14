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
    _emailController.text = 'cabanilla.sherwen@dnsc.edu.ph'; // Premade for dev
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
    } catch (e) {
      // Firebase may already be initialized
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
        String uid = userCredential.user!.uid;
        DocumentSnapshot adminDoc =
            await FirebaseFirestore.instance
                .collection('admins')
                .doc(uid)
                .get();
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
          setState(() {
            _errorMessage = 'You are not registered as an admin.';
            _isLoading = false;
          });
        }
      } on FirebaseAuthException catch (e) {
        String errorMsg;
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
            errorMsg = 'Too many failed attempts. Please try again later.';
            break;
          case 'invalid-credential':
            errorMsg = 'Invalid email or password. Please check and try again.';
            break;
          case 'network-request-failed':
            errorMsg = 'Network error. Please check your connection.';
            break;
          default:
            errorMsg = e.message ?? 'Login failed. Please try again.';
        }
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'An unexpected error occurred. Please try again.';
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
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('admins')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'This email is not registered as an admin.';
        });
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Password Reset'),
              content: Text('A password reset link has been sent to $email.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Failed to send reset email.';
      });
    }
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
