import 'package:flutter/material.dart';
import '../models/user_store.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(24),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.network(imageUrl, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildLoadingDialog(String message) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final users = await UserStore.getUsers();
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading users: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final filtered =
        _users.where((user) {
            final query = _searchQuery.toLowerCase();
            final matchesSearch =
                user['name'].toLowerCase().contains(query) ||
                user['email'].toLowerCase().contains(query) ||
                user['role'].toLowerCase().contains(query);

            // Handle different filter types
            bool matchesFilter = false;
            if (_selectedFilter == 'All') {
              matchesFilter = true;
            } else if (_selectedFilter == 'Pending' ||
                _selectedFilter == 'Active') {
              // Filter by status
              matchesFilter =
                  user['status'].toLowerCase() == _selectedFilter.toLowerCase();
            } else if (_selectedFilter == 'Expert' ||
                _selectedFilter == 'Farmer') {
              // Filter by role
              matchesFilter =
                  user['role'].toLowerCase() == _selectedFilter.toLowerCase();
            }

            return matchesSearch && matchesFilter;
          }).toList()
          ..sort((a, b) => a['name'].compareTo(b['name']));

    return filtered;
  }

  void _showEditDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    final addressController = TextEditingController(
      text: user['address'] ?? '',
    );
    final formKey = GlobalKey<FormState>();
    String selectedStatus = user['status'];
    String selectedRole = user['role'];
    final String profileImageUrl =
        (user['profileImage'] as String? ?? '').trim();

    // Create a list of all possible roles, including the current user's role
    final allRoles = ['expert', 'farmer'];
    if (!allRoles.contains(selectedRole)) {
      allRoles.add(selectedRole);
    }

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap:
                                  profileImageUrl.isNotEmpty
                                      ? () => _showImagePreview(profileImageUrl)
                                      : null,
                              child: Tooltip(
                                message:
                                    profileImageUrl.isNotEmpty
                                        ? 'Click to enlarge'
                                        : 'No profile photo',
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage:
                                      profileImageUrl.isNotEmpty
                                          ? NetworkImage(profileImageUrl)
                                              as ImageProvider<Object>?
                                          : null,
                                  child:
                                      profileImageUrl.isEmpty
                                          ? const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                          )
                                          : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit User',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    user['name'],
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Form(
                        key: formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                hintText: 'Enter full name',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Name is required'
                                          : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'name@example.com',
                                prefixIcon: Icon(Icons.email_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return 'Email is required';
                                final emailRegex = RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                );
                                if (!emailRegex.hasMatch(value)) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                hintText: 'e.g. 09123456789',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: addressController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                hintText: 'Street, City, etc.',
                                prefixIcon: Icon(Icons.home_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: selectedStatus,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                prefixIcon: Icon(Icons.verified_outlined),
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  ['pending', 'active']
                                      .map(
                                        (status) => DropdownMenuItem(
                                          value: status,
                                          child: Text(status.toUpperCase()),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) => selectedStatus = value!,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: selectedRole,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                prefixIcon: Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  allRoles
                                      .map(
                                        (role) => DropdownMenuItem(
                                          value: role,
                                          child: Text(role.toUpperCase()),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) => selectedRole = value!,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () async {
                            if (!(formKey.currentState?.validate() ?? false))
                              return;

                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder:
                                  (context) => _buildLoadingDialog('Saving...'),
                            );

                            try {
                              final success =
                                  await UserStore.updateUser(user['id'], {
                                    'name': nameController.text.trim(),
                                    'email': emailController.text.trim(),
                                    'phone': phoneController.text.trim(),
                                    'address': addressController.text.trim(),
                                    'status': selectedStatus,
                                    'role': selectedRole,
                                  });

                              Navigator.pop(context);

                              if (success) {
                                Navigator.pop(context);
                                _loadUsers();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${user['name']} updated successfully',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                await cf.FirebaseFirestore.instance
                                    .collection('activities')
                                    .add({
                                      'action': 'Updated user data',
                                      'user': nameController.text,
                                      'type': 'update',
                                      'color': Colors.blue.value,
                                      'icon': Icons.edit.codePoint,
                                      'timestamp':
                                          cf.FieldValue.serverTimestamp(),
                                    });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to update user. Please try again.',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error updating user: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          child: const Text('Save Changes'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'User Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loadUsers,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search... (name, email, or role)',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _selectedFilter,
                items:
                    ['All', 'Pending', 'Active', 'Expert', 'Farmer']
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          ),
                        )
                        .toList(),
                onChanged:
                    (value) => setState(() => _selectedFilter = value ?? 'All'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('Phone Number')),
                                DataColumn(label: Text('Address')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Role')),
                                DataColumn(label: Text('Registered')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows:
                                  _filteredUsers
                                      .map(
                                        (user) => DataRow(
                                          cells: [
                                            DataCell(
                                              Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor:
                                                        Colors.grey.shade200,
                                                    backgroundImage:
                                                        (user['profileImage'] !=
                                                                    null &&
                                                                (user['profileImage']
                                                                        as String)
                                                                    .trim()
                                                                    .isNotEmpty)
                                                            ? NetworkImage(
                                                                  (user['profileImage']
                                                                          as String)
                                                                      .trim(),
                                                                )
                                                                as ImageProvider<
                                                                  Object
                                                                >?
                                                            : null,
                                                    child:
                                                        (user['profileImage'] ==
                                                                    null ||
                                                                (user['profileImage']
                                                                        as String)
                                                                    .trim()
                                                                    .isEmpty)
                                                            ? const Icon(
                                                              Icons.person,
                                                              size: 16,
                                                              color:
                                                                  Colors.grey,
                                                            )
                                                            : null,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(user['name']),
                                                ],
                                              ),
                                            ),
                                            DataCell(Text(user['email'])),
                                            DataCell(Text(user['phone'] ?? '')),
                                            DataCell(
                                              Text(user['address'] ?? ''),
                                            ),
                                            DataCell(
                                              Text(
                                                user['status'].toUpperCase(),
                                                style: TextStyle(
                                                  color: _getStatusColor(
                                                    user['status'],
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                user['role'].toUpperCase(),
                                                style: TextStyle(
                                                  color: _getRoleColor(
                                                    user['role'],
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(user['registeredAt']),
                                            ),
                                            DataCell(
                                              Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                    ),
                                                    tooltip: 'Edit User',
                                                    onPressed:
                                                        () => _showEditDialog(
                                                          user,
                                                        ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      color: Colors.red,
                                                    ),
                                                    tooltip: 'Delete User',
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder:
                                                            (
                                                              context,
                                                            ) => AlertDialog(
                                                              title: const Text(
                                                                'Delete User',
                                                              ),
                                                              content: Text(
                                                                'Are you sure you want to delete "${user['name']}"?',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed:
                                                                      () => Navigator.pop(
                                                                        context,
                                                                      ),
                                                                  child:
                                                                      const Text(
                                                                        'Cancel',
                                                                      ),
                                                                ),
                                                                ElevatedButton(
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                    foregroundColor:
                                                                        Colors
                                                                            .white,
                                                                    textStyle: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                  onPressed: () async {
                                                                    // Show loading
                                                                    showDialog(
                                                                      context:
                                                                          context,
                                                                      barrierDismissible:
                                                                          false,
                                                                      builder:
                                                                          (
                                                                            context,
                                                                          ) => _buildLoadingDialog(
                                                                            'Deleting...',
                                                                          ),
                                                                    );
                                                                    final success =
                                                                        await UserStore.deleteUser(
                                                                          user['id'],
                                                                        );
                                                                    Navigator.pop(
                                                                      context,
                                                                    ); // Close loading
                                                                    Navigator.pop(
                                                                      context,
                                                                    ); // Close confirm dialog
                                                                    if (success) {
                                                                      await cf
                                                                          .FirebaseFirestore
                                                                          .instance
                                                                          .collection(
                                                                            'activities',
                                                                          )
                                                                          .add({
                                                                            'action':
                                                                                'Deleted user',
                                                                            'user':
                                                                                user['name'],
                                                                            'type':
                                                                                'delete',
                                                                            'color':
                                                                                Colors.red.value,
                                                                            'icon':
                                                                                Icons.delete.codePoint,
                                                                            'timestamp':
                                                                                cf.FieldValue.serverTimestamp(),
                                                                          });
                                                                      _loadUsers();
                                                                    } else {
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        const SnackBar(
                                                                          content: Text(
                                                                            'Failed to delete user. Please try again.',
                                                                          ),
                                                                          backgroundColor:
                                                                              Colors.red,
                                                                        ),
                                                                      );
                                                                    }
                                                                  },
                                                                  child:
                                                                      const Text(
                                                                        'Delete',
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'expert':
        return const Color.fromARGB(255, 31, 3, 133); // violet
      case 'farmer':
        return const Color.fromARGB(255, 255, 0, 0);
      default:
        return Colors.grey;
    }
  }
}
