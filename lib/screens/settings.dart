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

  Future<void> _editAdminName() async {
    final controller = TextEditingController(text: _adminName ?? 'Admin');
    final newName = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Admin Name'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Admin Name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (newName != null && newName.isNotEmpty) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('admins')
              .doc(user.uid)
              .update({'adminName': newName});
          setState(() => _adminName = newName);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Admin name updated!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update name: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                          await user.updateEmail(newEmail);
                          await FirebaseFirestore.instance
                              .collection('admins')
                              .doc(user.uid)
                              .update({'email': newEmail});
                          setState(() => _email = newEmail);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Email updated!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update email: ${e.message}',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update email: $e'),
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
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Current Password',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: newPasswordController,
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText: 'New Password',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller:
                                                confirmPasswordController,
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Confirm New Password',
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
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () =>
                                                  Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            final current =
                                                currentPasswordController.text
                                                    .trim();
                                            final newPass =
                                                newPasswordController.text
                                                    .trim();
                                            final confirm =
                                                confirmPasswordController.text
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
                                            try {
                                              final user =
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser;
                                              if (user != null &&
                                                  user.email != null) {
                                                final cred =
                                                    EmailAuthProvider.credential(
                                                      email: user.email!,
                                                      password: current,
                                                    );
                                                await user
                                                    .reauthenticateWithCredential(
                                                      cred,
                                                    );
                                                await user.updatePassword(
                                                  newPass,
                                                );
                                                Navigator.pop(context, true);
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
                                              setState(
                                                () =>
                                                    errorMessage =
                                                        e.message ??
                                                        'Failed to change password.',
                                              );
                                            } catch (e) {
                                              setState(
                                                () =>
                                                    errorMessage =
                                                        'Failed to change password.',
                                              );
                                            }
                                          },
                                          child: const Text('Save'),
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
                SwitchListTile(
                  secondary: const Icon(Icons.email),
                  title: const Text('Email Notifications'),
                  subtitle: const Text('Receive notifications via email'),
                  value: _emailNotifications,
                  onChanged: (bool value) {
                    setState(() {
                      _emailNotifications = value;
                    });
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
