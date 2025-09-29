import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_login.dart';

class Settings extends StatefulWidget {
  final VoidCallback? onViewReports;
  const Settings({Key? key, this.onViewReports}) : super(key: key);

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool _emailNotifications = true;
  String _selectedLanguage = 'English';
  String? _adminName;
  String? _email =
      FirebaseAuth.instance.currentUser?.email ?? 'admin@example.com';

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
          setState(() {
            _adminName = data['adminName'] ?? 'Admin';
            _email = updatedUser?.email ?? data['email'];
            _emailNotifications = data['notificationPrefs']?['email'] ?? true;
          });
        }
      }
    } catch (e) {
      print('Failed to refresh admin data: $e');
    }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  subtitle: Text(_email ?? 'admin@example.com'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh email status',
                    onPressed: () async {
                      await _refreshAdminData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Email status refreshed'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    final controller = TextEditingController(
                      text: _email ?? 'admin@example.com',
                    );
                    final newEmail = await showDialog<String>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('Edit Email'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed:
                                    () => Navigator.pop(
                                      context,
                                      controller.text.trim(),
                                    ),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                    );
                    if (newEmail != null &&
                        newEmail.isNotEmpty &&
                        newEmail != _email) {
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          // Use verifyBeforeUpdateEmail instead of updateEmail
                          // This sends a verification email to the new address first
                          await user.verifyBeforeUpdateEmail(newEmail);

                          // Show success message explaining the verification process
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Verification email sent to $newEmail. Please check your inbox and click the link to complete the email change.',
                              ),
                              backgroundColor: Colors.blue,
                              duration: const Duration(seconds: 6),
                            ),
                          );

                          // Log email change attempt (with error handling)
                          try {
                            await FirebaseFirestore.instance
                                .collection('activities')
                                .add({
                                  'action':
                                      'Email change verification sent to "$newEmail"',
                                  'user': _adminName ?? 'Admin',
                                  'type': 'profile_update',
                                  'color': Colors.purple.value,
                                  'icon': Icons.email.codePoint,
                                  'timestamp': FieldValue.serverTimestamp(),
                                });
                          } catch (e) {
                            print('Failed to log email change activity: $e');
                          }

                          // Note: We don't update the local email state here since the change
                          // isn't complete until the user clicks the verification link
                        }
                      } on FirebaseAuthException catch (e) {
                        String errorMessage =
                            'Failed to send verification email.';
                        switch (e.code) {
                          case 'invalid-email':
                            errorMessage =
                                'Please enter a valid email address.';
                            break;
                          case 'email-already-in-use':
                            errorMessage =
                                'This email is already in use by another account.';
                            break;
                          case 'requires-recent-login':
                            errorMessage =
                                'Please log out and log back in, then try again.';
                            break;
                          default:
                            errorMessage =
                                e.message ??
                                'Failed to send verification email.';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to send verification email: $e',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
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
                            final result = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) {
                                return StatefulBuilder(
                                  builder: (context, setState) {
                                    return AlertDialog(
                                      title: const Text('Change Password'),
                                      content: Column(
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
                                                    if (newPass != confirm) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'New passwords do not match.',
                                                      );
                                                      return;
                                                    }
                                                    if (newPass.length < 6) {
                                                      setState(
                                                        () =>
                                                            errorMessage =
                                                                'New password must be at least 6 characters long.',
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
                                                        errorMessage =
                                                            e.message ??
                                                            'Failed to change password.';
                                                      });
                                                    } catch (e) {
                                                      setState(() {
                                                        isLoading = false;
                                                        errorMessage =
                                                            'Failed to change password.';
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
          const SizedBox(height: 16),

          // Session
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Session',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
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
                          color: isHovered ? Colors.red.withOpacity(0.1) : null,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text(
                            'Logout',
                            style: TextStyle(color: Colors.red),
                          ),
                          onTap: () async {
                            final shouldLogout = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text('Confirm Logout'),
                                    content: const Text(
                                      'Are you sure you want to logout?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.of(
                                              context,
                                            ).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () =>
                                                Navigator.of(context).pop(true),
                                        child: const Text('Logout'),
                                      ),
                                    ],
                                  ),
                            );
                            if (shouldLogout == true) {
                              // Log admin logout before signing out
                              try {
                                await FirebaseFirestore.instance
                                    .collection('activities')
                                    .add({
                                      'action': 'Admin logged out',
                                      'user': _adminName ?? 'Admin',
                                      'type': 'logout',
                                      'color': Colors.orange.value,
                                      'icon': Icons.logout.codePoint,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                              } catch (e) {
                                // Continue with logout even if logging fails
                                print('Failed to log logout activity: $e');
                              }

                              await FirebaseAuth.instance.signOut();
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) => AdminLogin(),
                                ),
                                (route) => false,
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
