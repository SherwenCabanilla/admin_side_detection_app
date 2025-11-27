import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Settings extends StatefulWidget {
  final VoidCallback? onViewReports;
  const Settings({Key? key, this.onViewReports}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool _emailNotifications = true;
  String? _adminName;
  String? _email; // Initialize as null, load from Firestore
  bool _isLoadingData = true; // Track loading state

  Future<void> _updateEmailNotificationPref(bool enabled) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('admins').doc(user.uid).set({
        'notificationPrefs': {'email': enabled},
      }, SetOptions(merge: true));

      // Log notification settings change (with error handling)
      try {
        // Get current admin name if not loaded yet
        String adminName = _adminName ?? 'Admin';
        if (_adminName == null) {
          final adminDoc =
              await FirebaseFirestore.instance
                  .collection('admins')
                  .doc(user.uid)
                  .get();
          if (adminDoc.exists) {
            adminName = adminDoc.data()?['adminName'] ?? 'Admin';
          }
        }

        await FirebaseFirestore.instance.collection('activities').add({
          'action':
              enabled
                  ? 'Email notifications enabled'
                  : 'Email notifications disabled',
          'user': adminName,
          'type': 'settings_change',
          'color': Colors.blue.value,
          'icon':
              enabled
                  ? Icons.notifications_active.codePoint
                  : Icons.notifications_off.codePoint,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Don't fail the notification update if activity logging fails
        print('Failed to log notification activity: $e');
      }

      setState(() => _emailNotifications = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Email notifications enabled'
                : 'Email notifications disabled',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update notifications: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editAdminName() async {
    final controller = TextEditingController(text: _adminName ?? 'Admin');
    bool isLoading = false;
    String? errorMessage;

    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Admin Name'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Admin Name',
                      hintText: 'Enter your display name',
                    ),
                    enabled: !isLoading,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Updating name...'),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      isLoading
                          ? null
                          : () async {
                            final newNameText = controller.text.trim();
                            if (newNameText.isEmpty) {
                              setState(() {
                                errorMessage = 'Admin name cannot be empty.';
                              });
                              return;
                            }
                            if (newNameText == (_adminName ?? 'Admin')) {
                              Navigator.pop(context); // No change needed
                              return;
                            }

                            // Start loading
                            setState(() {
                              isLoading = true;
                              errorMessage = null;
                            });

                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null) {
                                final oldName = _adminName ?? 'Admin';
                                await FirebaseFirestore.instance
                                    .collection('admins')
                                    .doc(user.uid)
                                    .update({'adminName': newNameText});

                                // Log admin profile update (with error handling)
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('activities')
                                      .add({
                                        'action':
                                            'Admin name updated from "$oldName" to "$newNameText"',
                                        'user': newNameText,
                                        'type': 'profile_update',
                                        'color': Colors.purple.value,
                                        'icon': Icons.person_outline.codePoint,
                                        'timestamp':
                                            FieldValue.serverTimestamp(),
                                      });
                                } catch (e) {
                                  print(
                                    'Failed to log profile update activity: $e',
                                  );
                                }

                                Navigator.pop(context, newNameText);
                              } else {
                                setState(() {
                                  isLoading = false;
                                  errorMessage = 'User not authenticated.';
                                });
                              }
                            } catch (e) {
                              setState(() {
                                isLoading = false;
                                errorMessage =
                                    'Failed to update name. Please try again.';
                              });
                            }
                          },
                  child:
                      isLoading
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
                          : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (newName != null && newName.isNotEmpty) {
      setState(() => _adminName = newName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin name updated!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Refresh admin data from Firestore
  Future<void> _refreshAdminData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Reload user data to get updated email
        await user.reload();
        final updatedUser = FirebaseAuth.instance.currentUser;

        // Get admin data from Firestore
        final adminDoc =
            await FirebaseFirestore.instance
                .collection('admins')
                .doc(user.uid)
                .get();

        if (adminDoc.exists && mounted) {
          final data = adminDoc.data() as Map<String, dynamic>;

          // If email was successfully changed, update Firestore collections
          if (updatedUser?.email != null &&
              updatedUser!.email != data['email'] &&
              data['pendingEmail'] == updatedUser.email) {
            // Email verification completed! Sync to Firestore
            try {
              await FirebaseFirestore.instance
                  .collection('admins')
                  .doc(user.uid)
                  .update({
                    'email': updatedUser.email,
                    'emailUpdatedAt': FieldValue.serverTimestamp(),
                  });

              // Also update users collection if it exists
              final userDoc =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .get();

              if (userDoc.exists) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .update({
                      'email': updatedUser.email,
                      'emailUpdatedAt': FieldValue.serverTimestamp(),
                    });
                print('✅ Email synced to both admins and users collections');
              }

              // Log the successful email change
              await FirebaseFirestore.instance.collection('activities').add({
                'action':
                    'Email successfully changed to "${updatedUser.email}"',
                'user': data['adminName'] ?? 'Admin',
                'type': 'profile_update',
                'color': Colors.green.value,
                'icon': Icons.check_circle.codePoint,
                'timestamp': FieldValue.serverTimestamp(),
              });
            } catch (e) {
              print('Failed to sync email to Firestore: $e');
            }
          }

          setState(() {
            _adminName = data['adminName'] ?? 'Admin';
            // Prioritize Firebase Auth email, fallback to Firestore only if auth email is null
            _email = updatedUser?.email ?? data['email'];
            _emailNotifications = data['notificationPrefs']?['email'] ?? true;
            _isLoadingData = false; // Data loaded successfully
          });
        } else if (mounted) {
          setState(() {
            _isLoadingData = false; // No data found but stop loading
          });
        }
      }
    } catch (e) {
      print('Failed to refresh admin data: $e');
      if (mounted) {
        setState(() {
          _isLoadingData = false; // Error occurred but stop loading
        });
      }
    }
  }

  // Comprehensive email change dialog with validation and confirmation
  Future<void> _showChangeEmailDialog() async {
    // Safety check: ensure email is loaded
    if (_email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for email to load or refresh'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool showPassword = false;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Change Email Address'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show current email
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Email:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  _email!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // New email input
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'New Email Address',
                        hintText: 'Enter new email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isLoading,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    // Password for re-authentication
                    TextField(
                      controller: passwordController,
                      obscureText: !showPassword,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Confirm your password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              showPassword = !showPassword;
                            });
                          },
                        ),
                      ),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 12),
                    // Warning message
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'A verification email will be sent to your new address. You must click the link to complete the change.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isLoading) ...[
                      const SizedBox(height: 16),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Processing email change...'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      isLoading
                          ? null
                          : () async {
                            final newEmail = controller.text.trim();
                            final password = passwordController.text.trim();

                            // Validation
                            if (newEmail.isEmpty) {
                              setState(() {
                                errorMessage =
                                    'Please enter a new email address.';
                              });
                              return;
                            }

                            // Email format validation
                            final emailRegex = RegExp(
                              r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                            );
                            if (!emailRegex.hasMatch(newEmail)) {
                              setState(() {
                                errorMessage =
                                    'Please enter a valid email address.';
                              });
                              return;
                            }

                            // Check if same as current
                            if (newEmail == _email) {
                              setState(() {
                                errorMessage =
                                    'New email is the same as current email.';
                              });
                              return;
                            }

                            // Check password provided
                            if (password.isEmpty) {
                              setState(() {
                                errorMessage =
                                    'Please enter your current password to continue.';
                              });
                              return;
                            }

                            // Show confirmation dialog
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text('Confirm Email Change'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Are you sure you want to change your email?',
                                        ),
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Text(
                                                    'From: ',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(_email!),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Text(
                                                    'To:   ',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      newEmail,
                                                      style: const TextStyle(
                                                        color: Colors.blue,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        child: const Text(
                                          'Confirm Change',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                            );

                            if (confirmed != true) return;

                            // Start loading
                            setState(() {
                              isLoading = true;
                              errorMessage = null;
                            });

                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null && user.email != null) {
                                // Re-authenticate first
                                final cred = EmailAuthProvider.credential(
                                  email: user.email!,
                                  password: password,
                                );
                                await user.reauthenticateWithCredential(cred);

                                // Get the current web URL for continuation
                                String? continueUrl;
                                try {
                                  // For web, use current origin
                                  continueUrl = Uri.base.origin;
                                } catch (e) {
                                  print('Could not get current URL: $e');
                                }

                                // Send verification email with action code settings
                                if (continueUrl != null) {
                                  final actionCodeSettings = ActionCodeSettings(
                                    url: continueUrl,
                                    handleCodeInApp: true,
                                  );
                                  await user.verifyBeforeUpdateEmail(
                                    newEmail,
                                    actionCodeSettings,
                                  );
                                } else {
                                  // Fallback without continuation URL
                                  await user.verifyBeforeUpdateEmail(newEmail);
                                }

                                // Update Firestore email in admins collection
                                await FirebaseFirestore.instance
                                    .collection('admins')
                                    .doc(user.uid)
                                    .update({
                                      'pendingEmail': newEmail,
                                      'pendingEmailTimestamp':
                                          FieldValue.serverTimestamp(),
                                    });

                                // Also update users collection if it exists (for dual accounts)
                                try {
                                  final userDoc =
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user.uid)
                                          .get();

                                  if (userDoc.exists) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .update({
                                          'pendingEmail': newEmail,
                                          'pendingEmailTimestamp':
                                              FieldValue.serverTimestamp(),
                                        });
                                    print(
                                      '✅ Updated users collection with pending email',
                                    );
                                  } else {
                                    print(
                                      'ℹ️ No users document found - admin-only account',
                                    );
                                  }
                                } catch (e) {
                                  print(
                                    '⚠️ Failed to update users collection: $e',
                                  );
                                  // Continue anyway - not critical
                                }

                                // Log email change attempt
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('activities')
                                      .add({
                                        'action':
                                            'Email change verification sent from "${_email}" to "$newEmail"',
                                        'user': _adminName ?? 'Admin',
                                        'type': 'profile_update',
                                        'color': Colors.purple.value,
                                        'icon': Icons.email.codePoint,
                                        'timestamp':
                                            FieldValue.serverTimestamp(),
                                      });
                                } catch (e) {
                                  print(
                                    'Failed to log email change activity: $e',
                                  );
                                }

                                Navigator.pop(context, true);

                                // Show success message
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Verification email sent to $newEmail.\n\nIMPORTANT: Check your inbox and click the verification link to complete the email change. After verifying, click the refresh button to update your email here.',
                                      ),
                                      backgroundColor: Colors.blue,
                                      duration: const Duration(seconds: 10),
                                      action: SnackBarAction(
                                        label: 'OK',
                                        textColor: Colors.white,
                                        onPressed: () {},
                                      ),
                                    ),
                                  );
                                }
                              }
                            } on FirebaseAuthException catch (e) {
                              setState(() {
                                isLoading = false;
                                switch (e.code) {
                                  case 'invalid-email':
                                    errorMessage =
                                        'Invalid email address format.';
                                    break;
                                  case 'email-already-in-use':
                                    errorMessage =
                                        'This email is already in use.';
                                    break;
                                  case 'wrong-password':
                                    errorMessage =
                                        'The password you entered is incorrect. Please try again.';
                                    break;
                                  case 'invalid-credential':
                                    errorMessage =
                                        'The password you entered is incorrect. Please check your password and try again.';
                                    break;
                                  case 'requires-recent-login':
                                    errorMessage =
                                        'Session expired. Please log out and log back in.';
                                    break;
                                  default:
                                    // Check if the error message contains password-related keywords
                                    final message = e.message ?? '';
                                    if (message.toLowerCase().contains('password') ||
                                        message.toLowerCase().contains('credential') ||
                                        message.toLowerCase().contains('incorrect')) {
                                      errorMessage =
                                          'The password you entered is incorrect. Please check your password and try again.';
                                    } else {
                                      errorMessage =
                                          'Failed to change email. ${message.isNotEmpty ? message : "Please try again."}';
                                    }
                                }
                              });
                            } catch (e) {
                              setState(() {
                                isLoading = false;
                                errorMessage =
                                    'An unexpected error occurred: $e';
                              });
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child:
                      isLoading
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
                            'Send Verification',
                            style: TextStyle(color: Colors.white),
                          ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Load admin data asynchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAdminData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Profile Settings
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Profile Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: () {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      return const Stream<
                        DocumentSnapshot<Map<String, dynamic>>
                      >.empty();
                    }
                    return FirebaseFirestore.instance
                        .collection('admins')
                        .doc(user.uid)
                        .snapshots();
                  }(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    _adminName = data?['adminName'] ?? _adminName ?? 'Admin';
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text('Edit Admin Name'),
                      subtitle: Text(_adminName ?? 'Admin'),
                      onTap: _editAdminName,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Edit Email'),
                  subtitle:
                      _isLoadingData
                          ? const Text('Loading...')
                          : Text(_email ?? 'No email found'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh email status',
                    onPressed: () async {
                      await _refreshAdminData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Email status refreshed'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  onTap:
                      _isLoadingData || _email == null
                          ? null // Disable if data is still loading or email is null
                          : () => _showChangeEmailDialog(),
                ),
                StatefulBuilder(
                  builder: (context, setState) {
                    bool isHovered = false;
                    return MouseRegion(
                      onEnter: (_) => setState(() => isHovered = true),
                      onExit: (_) => setState(() => isHovered = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color:
                              isHovered ? Colors.green.withOpacity(0.1) : null,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.lock),
                          title: const Text('Change Password'),
                          subtitle: const Text(
                            'Update your admin account password',
                          ),
                          onTap: () async {
                            final currentPasswordController =
                                TextEditingController();
                            final newPasswordController =
                                TextEditingController();
                            final confirmPasswordController =
                                TextEditingController();
                            String? errorMessage;
                            bool isLoading = false;
                            bool showCurrentPassword = false;
                            bool showNewPassword = false;
                            bool showConfirmPassword = false;
                            await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) {
                                return StatefulBuilder(
                                  builder: (context, setState) {
                                    return AlertDialog(
                                      title: const Text('Change Password'),
                                      contentPadding: const EdgeInsets.fromLTRB(
                                          24.0, 20.0, 24.0, 24.0),
                                      content: SizedBox(
                                        width: 500,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                          TextField(
                                            controller:
                                                currentPasswordController,
                                            obscureText: !showCurrentPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Current Password',
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  showCurrentPassword
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    showCurrentPassword =
                                                        !showCurrentPassword;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: newPasswordController,
                                            obscureText: !showNewPassword,
                                            decoration: InputDecoration(
                                              labelText: 'New Password',
                                              helperText:
                                                  'Must be 8+ characters with uppercase, lowercase, number, and special character',
                                              helperMaxLines: 2,
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  showNewPassword
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    showNewPassword =
                                                        !showNewPassword;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller:
                                                confirmPasswordController,
                                            obscureText: !showConfirmPassword,
                                            decoration: InputDecoration(
                                              labelText: 'Confirm New Password',
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  showConfirmPassword
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    showConfirmPassword =
                                                        !showConfirmPassword;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                          if (errorMessage != null) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              errorMessage!,
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                          if (isLoading) ...[
                                            const SizedBox(height: 16),
                                            const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                                SizedBox(width: 12),
                                                Text('Changing password...'),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              isLoading
                                                  ? null
                                                  : () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed:
                                              isLoading
                                                  ? null
                                                  : () async {
                                                    final current =
                                                        currentPasswordController
                                                            .text
                                                            .trim();
                                                    final newPass =
                                                        newPasswordController
                                                            .text
                                                            .trim();
                                                    final confirm =
                                                        confirmPasswordController
                                                            .text
                                                            .trim();
                                                    // Validation
                                                    if (current.isEmpty ||
                                                        newPass.isEmpty ||
                                                        confirm.isEmpty) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'All fields are required.',
                                                      );
                                                      return;
                                                    }

                                                    // Check if new password is same as current
                                                    if (newPass == current) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'New password must be different from your current password.',
                                                      );
                                                      return;
                                                    }

                                                    // Check if passwords match
                                                    if (newPass != confirm) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'New passwords do not match. Please try again.',
                                                      );
                                                      return;
                                                    }

                                                    // Password strength validation
                                                    if (newPass.length < 8) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'Password must be at least 8 characters long.',
                                                      );
                                                      return;
                                                    }

                                                    // Check for uppercase letter
                                                    if (!newPass.contains(
                                                        RegExp(r'[A-Z]'))) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'Password must contain at least one uppercase letter (A-Z).',
                                                      );
                                                      return;
                                                    }

                                                    // Check for lowercase letter
                                                    if (!newPass.contains(
                                                        RegExp(r'[a-z]'))) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'Password must contain at least one lowercase letter (a-z).',
                                                      );
                                                      return;
                                                    }

                                                    // Check for number
                                                    if (!newPass.contains(
                                                        RegExp(r'[0-9]'))) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'Password must contain at least one number (0-9).',
                                                      );
                                                      return;
                                                    }

                                                    // Check for special character
                                                    if (!newPass.contains(
                                                        RegExp(
                                                            r'[!@#$%^&*(),.?":{}|<>]'))) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'Password must contain at least one special character (!@#\$%^&* etc.).',
                                                      );
                                                      return;
                                                    }

                                                    // Start loading
                                                    setState(() {
                                                      isLoading = true;
                                                      errorMessage = null;
                                                    });

                                                    try {
                                                      final user =
                                                          FirebaseAuth
                                                              .instance
                                                              .currentUser;
                                                      if (user != null &&
                                                          user.email != null) {
                                                        final cred =
                                                            EmailAuthProvider.credential(
                                                              email:
                                                                  user.email!,
                                                              password: current,
                                                            );
                                                        await user
                                                            .reauthenticateWithCredential(
                                                              cred,
                                                            );
                                                        await user
                                                            .updatePassword(
                                                              newPass,
                                                            );

                                                        // Log password change (with error handling)
                                                        try {
                                                          await FirebaseFirestore
                                                              .instance
                                                              .collection(
                                                                'activities',
                                                              )
                                                              .add({
                                                                'action':
                                                                    'Admin password changed',
                                                                'user':
                                                                    _adminName ??
                                                                    'Admin',
                                                                'type':
                                                                    'password_change',
                                                                'color':
                                                                    Colors
                                                                        .amber
                                                                        .value,
                                                                'icon':
                                                                    Icons
                                                                        .security
                                                                        .codePoint,
                                                                'timestamp':
                                                                    FieldValue.serverTimestamp(),
                                                              });
                                                        } catch (e) {
                                                          print(
                                                            'Failed to log password change activity: $e',
                                                          );
                                                        }

                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        );
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Password changed successfully!',
                                                            ),
                                                            backgroundColor:
                                                                Colors.green,
                                                          ),
                                                        );
                                                      }
                                                    } on FirebaseAuthException catch (
                                                      e
                                                    ) {
                                                      setState(() {
                                                        isLoading = false;
                                                        switch (e.code) {
                                                          case 'wrong-password':
                                                            errorMessage =
                                                                'The current password you entered is incorrect. Please try again.';
                                                            break;
                                                          case 'invalid-credential':
                                                            errorMessage =
                                                                'The current password you entered is incorrect. Please check and try again.';
                                                            break;
                                                          case 'weak-password':
                                                            errorMessage =
                                                                'The password is too weak. Please use a stronger password.';
                                                            break;
                                                          case 'requires-recent-login':
                                                            errorMessage =
                                                                'Session expired. Please log out and log back in to change your password.';
                                                            break;
                                                          default:
                                                            // Check if the error message contains password-related keywords
                                                            final message =
                                                                e.message ?? '';
                                                            if (message
                                                                    .toLowerCase()
                                                                    .contains(
                                                                        'password') ||
                                                                message
                                                                    .toLowerCase()
                                                                    .contains(
                                                                        'credential') ||
                                                                message
                                                                    .toLowerCase()
                                                                    .contains(
                                                                        'incorrect')) {
                                                              errorMessage =
                                                                  'The current password you entered is incorrect. Please check and try again.';
                                                            } else {
                                                              errorMessage =
                                                                  'Failed to change password. ${message.isNotEmpty ? message : "Please try again."}';
                                                            }
                                                        }
                                                      });
                                                    } catch (e) {
                                                      setState(() {
                                                        isLoading = false;
                                                        errorMessage =
                                                            'An unexpected error occurred. Please try again.';
                                                      });
                                                    }
                                                  },
                                          child:
                                              isLoading
                                                  ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(Colors.white),
                                                    ),
                                                  )
                                                  : const Text('Save'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Notification Settings
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Notification Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: () {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      return const Stream<
                        DocumentSnapshot<Map<String, dynamic>>
                      >.empty();
                    }
                    return FirebaseFirestore.instance
                        .collection('admins')
                        .doc(user.uid)
                        .snapshots();
                  }(),
                  builder: (context, snapshot) {
                    final dynamic raw = snapshot.data?.data();
                    final Map<String, dynamic> data =
                        raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                    final Map<String, dynamic> prefs =
                        data['notificationPrefs'] is Map
                            ? Map<String, dynamic>.from(
                              data['notificationPrefs'] as Map,
                            )
                            : <String, dynamic>{};
                    final bool currentPref =
                        (prefs['email'] as bool?) ?? _emailNotifications;
                    return SwitchListTile(
                      secondary: const Icon(Icons.email),
                      title: const Text('Email Notifications'),
                      subtitle: const Text('Receive notifications via email'),
                      value: currentPref,
                      onChanged:
                          (bool value) => _updateEmailNotificationPref(value),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
