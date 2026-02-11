import 'dart:async';
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
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _selectedUserId;

  // Cache for filtered users
  List<Map<String, dynamic>>? _cachedFilteredUsers;
  String _lastSearchQuery = '';
  String _lastFilter = '';

  // Debounce timer for search
  Timer? _searchDebounce;

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
        // Clear cache when loading new data
        _cachedFilteredUsers = null;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    // Use cached result if search query and filter haven't changed
    if (_cachedFilteredUsers != null &&
        _lastSearchQuery == _searchQuery &&
        _lastFilter == _selectedFilter) {
      return _cachedFilteredUsers!;
    }

    // Update cache markers
    _lastSearchQuery = _searchQuery;
    _lastFilter = _selectedFilter;

    // Perform filtering
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

    // Cache the result
    _cachedFilteredUsers = filtered;
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
                                hintText: '09123456789 or +639123456789',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                                helperText: 'Philippine mobile number format',
                              ),
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) {
                                  return 'Phone number is required';
                                }

                                // Remove any spaces or dashes
                                final cleanedValue = value.replaceAll(
                                  RegExp(r'[\s\-]'),
                                  '',
                                );

                                // Check if contains only numbers, + and spaces/dashes
                                if (!RegExp(r'^[\d\+\s\-]+$').hasMatch(value)) {
                                  return 'Phone number can only contain numbers';
                                }

                                // Philippine phone number formats:
                                // 09XXXXXXXXX (11 digits starting with 09)
                                // +639XXXXXXXXX (13 characters starting with +639)
                                // 639XXXXXXXXX (12 digits starting with 639)

                                if (cleanedValue.startsWith('+639')) {
                                  if (cleanedValue.length != 13) {
                                    return 'Format: +639XXXXXXXXX (13 digits)';
                                  }
                                } else if (cleanedValue.startsWith('639')) {
                                  if (cleanedValue.length != 12) {
                                    return 'Format: 639XXXXXXXXX (12 digits)';
                                  }
                                } else if (cleanedValue.startsWith('09')) {
                                  if (cleanedValue.length != 11) {
                                    return 'Format: 09XXXXXXXXX (11 digits)';
                                  }
                                } else {
                                  return 'Must start with 09, 639, or +639';
                                }

                                return null;
                              },
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
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }

                            final bool? confirm = await showDialog<bool>(
                              context: context,
                              builder:
                                  (ctx) => AlertDialog(
                                    title: const Text('Confirm changes'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Name: ' + nameController.text.trim(),
                                        ),
                                        Text(
                                          'Email: ' +
                                              emailController.text.trim(),
                                        ),
                                        if (phoneController.text
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            'Phone: ' +
                                                phoneController.text.trim(),
                                          ),
                                        if (addressController.text
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            'Address: ' +
                                                addressController.text.trim(),
                                          ),
                                        Text('Status: ' + selectedStatus),
                                        Text('Role: ' + selectedRole),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed:
                                            () => Navigator.of(ctx).pop(true),
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                            );
                            if (confirm != true) return;

                            // Capture context and user info before async operations
                            final dialogContext = context;
                            final userName = user['name'] as String;
                            final userId = user['id'] as String;
                            final nameValue = nameController.text.trim();
                            final emailValue = emailController.text.trim();
                            final phoneValue = phoneController.text.trim();
                            final addressValue = addressController.text.trim();

                            // Show loading dialog
                            showDialog(
                              context: dialogContext,
                              barrierDismissible: false,
                              builder:
                                  (ctx) => _buildLoadingDialog('Saving...'),
                            );

                            try {
                              final success =
                                  await UserStore.updateUser(userId, {
                                    'name': nameValue,
                                    'email': emailValue,
                                    'phone': phoneValue,
                                    'address': addressValue,
                                    'status': selectedStatus,
                                    'role': selectedRole,
                                  });

                              // Close loading dialog
                              if (Navigator.canPop(dialogContext)) {
                                Navigator.of(dialogContext).pop();
                              }

                              // Close edit dialog
                              if (Navigator.canPop(dialogContext)) {
                                Navigator.of(dialogContext).pop();
                              }

                              if (success) {
                                // Log activity (don't await before showing dialog)
                                cf.FirebaseFirestore.instance
                                    .collection('activities')
                                    .add({
                                      'action': 'Updated user data',
                                      'user': nameValue,
                                      'type': 'update',
                                      'color': Colors.blue.value,
                                      'icon': Icons.edit.codePoint,
                                      'timestamp':
                                          cf.FieldValue.serverTimestamp(),
                                    });

                                // Show success dialog BEFORE reloading users
                                if (mounted) {
                                  await showDialog(
                                    context: dialogContext,
                                    barrierDismissible: false,
                                    builder:
                                        (ctx) => AlertDialog(
                                          title: Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: Colors.green,
                                                size: 28,
                                              ),
                                              SizedBox(width: 12),
                                              Text('Success'),
                                            ],
                                          ),
                                          content: Text(
                                            '$userName has been updated successfully!',
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              onPressed:
                                                  () => Navigator.of(ctx).pop(),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                  );
                                }

                                // Reload users AFTER dialog is dismissed
                                _loadUsers();
                              } else {
                                // Show error dialog
                                if (mounted) {
                                  showDialog(
                                    context: dialogContext,
                                    builder:
                                        (ctx) => AlertDialog(
                                          title: Row(
                                            children: [
                                              Icon(
                                                Icons.error,
                                                color: Colors.red,
                                                size: 28,
                                              ),
                                              SizedBox(width: 12),
                                              Text('Error'),
                                            ],
                                          ),
                                          content: const Text(
                                            'Failed to update user. Please try again.',
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              onPressed:
                                                  () => Navigator.of(ctx).pop(),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                  );
                                }
                              }
                            } catch (e) {
                              // Close any open dialogs
                              if (Navigator.canPop(dialogContext)) {
                                Navigator.of(dialogContext).pop();
                              }
                              if (Navigator.canPop(dialogContext)) {
                                Navigator.of(dialogContext).pop();
                              }

                              // Show error dialog
                              if (mounted) {
                                showDialog(
                                  context: dialogContext,
                                  builder:
                                      (ctx) => AlertDialog(
                                        title: Row(
                                          children: [
                                            Icon(
                                              Icons.error,
                                              color: Colors.red,
                                              size: 28,
                                            ),
                                            SizedBox(width: 12),
                                            Text('Error'),
                                          ],
                                        ),
                                        content: Text(
                                          'Error updating user: $e',
                                        ),
                                        actions: [
                                          ElevatedButton(
                                            onPressed:
                                                () => Navigator.of(ctx).pop(),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                );
                              }
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
    _searchDebounce?.cancel();
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
                  onChanged: (value) {
                    // Cancel previous timer
                    if (_searchDebounce?.isActive ?? false) {
                      _searchDebounce!.cancel();
                    }
                    // Start new timer
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () {
                        setState(() {
                          _searchQuery = value;
                          _cachedFilteredUsers = null;
                        });
                      },
                    );
                  },
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
                onChanged: (value) {
                  setState(() {
                    _selectedFilter = value ?? 'All';
                    _cachedFilteredUsers = null;
                  });
                },
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
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Container(
                            width: double.infinity,
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                // Control the ripple/splash animation duration
                                splashFactory: InkRipple.splashFactory,
                              ),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.5), // Name
                                  1: FlexColumnWidth(2.0), // Email
                                  2: FlexColumnWidth(1.2), // Phone Number
                                  3: FlexColumnWidth(2.0), // Address
                                  4: FlexColumnWidth(1.0), // Status
                                  5: FlexColumnWidth(1.0), // Role
                                  6: FlexColumnWidth(1.2), // Registered
                                  7: FlexColumnWidth(1.2), // Accepted
                                  8: FlexColumnWidth(1.0), // Actions
                                },
                                border: TableBorder(
                                  horizontalInside: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  verticalInside: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  top: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  left: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  right: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                children: [
                                  // Header row
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                    ),
                                    children: [
                                      _buildHeaderCell('Name'),
                                      _buildHeaderCell('Email'),
                                      _buildHeaderCell('Phone Number'),
                                      _buildHeaderCell('Address'),
                                      _buildHeaderCell('Status'),
                                      _buildHeaderCell('Role'),
                                      _buildHeaderCell('Registered'),
                                      _buildHeaderCell('Accepted'),
                                      _buildHeaderCell('Actions'),
                                    ],
                                  ),
                                  // Data rows
                                  ..._filteredUsers.map((user) {
                                    final isSelected = _selectedUserId == user['id'];
                                    return TableRow(
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0x2D2A9D32)
                                            : null,
                                      ),
                                      children: [
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['name'],
                                            child: Row(
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
                                                            color: Colors.grey,
                                                          )
                                                          : null,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    user['name'],
                                                    textAlign: TextAlign.center,
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['email'],
                                            child: Text(
                                              user['email'],
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['phone'] ?? '',
                                            child: Text(
                                              user['phone'] ?? '',
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['address'] ?? '',
                                            child: Text(
                                              user['address'] ?? '',
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Text(
                                            user['status'].toUpperCase(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _getStatusColor(
                                                user['status'],
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Text(
                                            user['role'].toUpperCase(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _getRoleColor(
                                                user['role'],
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['registeredAt'],
                                            child: Text(
                                              user['registeredAt'],
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Tooltip(
                                            message: user['acceptedAt'] ?? '—',
                                            child: Text(
                                              user['acceptedAt'] ?? '—',
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _selectedUserId =
                                                  isSelected ? null : user['id'];
                                            });
                                          },
                                        ),
                                        _buildDataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
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
                                                                    child: const Text(
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
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                    onPressed: () async {
                                                                      // Capture context and user info before async operations
                                                                      final dialogContext =
                                                                          context;
                                                                      final userName =
                                                                          user['name']
                                                                              as String;
                                                                      final userId =
                                                                          user['id']
                                                                              as String;

                                                                      // Show loading dialog
                                                                      showDialog(
                                                                        context:
                                                                            dialogContext,
                                                                        barrierDismissible:
                                                                            false,
                                                                        builder:
                                                                            (
                                                                              ctx,
                                                                            ) => _buildLoadingDialog(
                                                                              'Deleting...',
                                                                            ),
                                                                      );

                                                                      try {
                                                                        final success =
                                                                            await UserStore.deleteUser(
                                                                              userId,
                                                                            );

                                                                        // Close loading dialog
                                                                        if (Navigator.canPop(
                                                                          dialogContext,
                                                                        )) {
                                                                          Navigator.of(
                                                                            dialogContext,
                                                                          ).pop();
                                                                        }

                                                                        // Close confirmation dialog
                                                                        if (Navigator.canPop(
                                                                          dialogContext,
                                                                        )) {
                                                                          Navigator.of(
                                                                            dialogContext,
                                                                          ).pop();
                                                                        }

                                                                        if (success) {
                                                                          // Log activity (don't await before showing dialog)
                                                                          cf.FirebaseFirestore.instance
                                                                              .collection(
                                                                                'activities',
                                                                              )
                                                                              .add({
                                                                                'action':
                                                                                    'Deleted user',
                                                                                'user':
                                                                                    userName,
                                                                                'type':
                                                                                    'delete',
                                                                                'color':
                                                                                    Colors.red.value,
                                                                                'icon':
                                                                                    Icons.delete.codePoint,
                                                                                'timestamp':
                                                                                    cf.FieldValue.serverTimestamp(),
                                                                              });

                                                                          // Show success dialog BEFORE reloading users
                                                                          if (mounted) {
                                                                            await showDialog(
                                                                              context:
                                                                                  dialogContext,
                                                                              barrierDismissible:
                                                                                  false,
                                                                              builder:
                                                                                  (
                                                                                    ctx,
                                                                                  ) => AlertDialog(
                                                                                    title: Row(
                                                                                      children: [
                                                                                        Icon(
                                                                                          Icons.check_circle,
                                                                                          color:
                                                                                              Colors.green,
                                                                                          size:
                                                                                              28,
                                                                                        ),
                                                                                        SizedBox(
                                                                                          width:
                                                                                              12,
                                                                                        ),
                                                                                        Text(
                                                                                          'Success',
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                    content: Text(
                                                                                      '$userName has been deleted successfully!',
                                                                                    ),
                                                                                    actions: [
                                                                                      ElevatedButton(
                                                                                        onPressed:
                                                                                            () =>
                                                                                                Navigator.of(
                                                                                                  ctx,
                                                                                                ).pop(),
                                                                                        style: ElevatedButton.styleFrom(
                                                                                          backgroundColor:
                                                                                              Colors.green,
                                                                                          foregroundColor:
                                                                                              Colors.white,
                                                                                        ),
                                                                                        child: const Text(
                                                                                          'OK',
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                            );
                                                                          }

                                                                          // Reload users AFTER dialog is dismissed
                                                                          _loadUsers();
                                                                        } else {
                                                                          // Show error dialog
                                                                          if (mounted) {
                                                                            showDialog(
                                                                              context:
                                                                                  dialogContext,
                                                                              builder:
                                                                                  (
                                                                                    ctx,
                                                                                  ) => AlertDialog(
                                                                                    title: Row(
                                                                                      children: [
                                                                                        Icon(
                                                                                          Icons.error,
                                                                                          color:
                                                                                              Colors.red,
                                                                                          size:
                                                                                              28,
                                                                                        ),
                                                                                        SizedBox(
                                                                                          width:
                                                                                              12,
                                                                                        ),
                                                                                        Text(
                                                                                          'Error',
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                    content: const Text(
                                                                                      'Failed to delete user. Please try again.',
                                                                                    ),
                                                                                    actions: [
                                                                                      ElevatedButton(
                                                                                        onPressed:
                                                                                            () =>
                                                                                                Navigator.of(
                                                                                                  ctx,
                                                                                                ).pop(),
                                                                                        style: ElevatedButton.styleFrom(
                                                                                          backgroundColor:
                                                                                              Colors.red,
                                                                                          foregroundColor:
                                                                                              Colors.white,
                                                                                        ),
                                                                                        child: const Text(
                                                                                          'OK',
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                            );
                                                                          }
                                                                        }
                                                                      } catch (
                                                                        e
                                                                      ) {
                                                                        // Close any open dialogs
                                                                        if (Navigator.canPop(
                                                                          dialogContext,
                                                                        )) {
                                                                          Navigator.of(
                                                                            dialogContext,
                                                                          ).pop();
                                                                        }
                                                                        if (Navigator.canPop(
                                                                          dialogContext,
                                                                        )) {
                                                                          Navigator.of(
                                                                            dialogContext,
                                                                          ).pop();
                                                                        }

                                                                        // Show error dialog
                                                                        if (mounted) {
                                                                          showDialog(
                                                                            context:
                                                                                dialogContext,
                                                                            builder:
                                                                                (
                                                                                  ctx,
                                                                                ) => AlertDialog(
                                                                                  title: Row(
                                                                                    children: [
                                                                                      Icon(
                                                                                        Icons.error,
                                                                                        color:
                                                                                            Colors.red,
                                                                                        size:
                                                                                            28,
                                                                                      ),
                                                                                      SizedBox(
                                                                                        width:
                                                                                            12,
                                                                                      ),
                                                                                      Text(
                                                                                        'Error',
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                  content: Text(
                                                                                    'Error deleting user: $e',
                                                                                  ),
                                                                                  actions: [
                                                                                    ElevatedButton(
                                                                                      onPressed:
                                                                                          () =>
                                                                                              Navigator.of(
                                                                                                ctx,
                                                                                              ).pop(),
                                                                                      style: ElevatedButton.styleFrom(
                                                                                        backgroundColor:
                                                                                            Colors.red,
                                                                                        foregroundColor:
                                                                                            Colors.white,
                                                                                      ),
                                                                                      child: const Text(
                                                                                        'OK',
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                          );
                                                                        }
                                                                      }
                                                                    },
                                                                    child: const Text(
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
                                  );
                                }).toList(),
                                ],
                              ),
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

  Widget _buildHeaderCell(String text) {
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataCell(Widget child, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DefaultTextStyle(
              style: const TextStyle(height: 1.2),
              child: child,
            ),
          ),
        ),
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
