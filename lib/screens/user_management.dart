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
            final matchesStatus =
                _selectedFilter == 'All' ||
                user['status'] == _selectedFilter.toLowerCase();
            return matchesSearch && matchesStatus;
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
    String selectedStatus = user['status'];
    String selectedRole = user['role'];

    // Create a list of all possible roles, including the current user's role
    final allRoles = ['expert', 'farmer'];
    if (!allRoles.contains(selectedRole)) {
      allRoles.add(selectedRole);
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Edit User: ${user['name']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Show loading
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (context) =>
                            const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    final success = await UserStore.updateUser(user['id'], {
                      'name': nameController.text,
                      'email': emailController.text,
                      'phone': phoneController.text,
                      'address': addressController.text,
                      'status': selectedStatus,
                      'role': selectedRole,
                    });

                    // Close loading dialog
                    Navigator.pop(context);

                    if (success) {
                      // Close edit dialog
                      Navigator.pop(context);

                      // Refresh the list
                      _loadUsers();

                      // Show success message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${user['name']} updated successfully'),
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
                            'timestamp': cf.FieldValue.serverTimestamp(),
                          });
                    } else {
                      // Show error message
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
                    // Close loading dialog
                    Navigator.pop(context);

                    // Show error message
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
                    ['All', 'Pending', 'Active']
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
                                            DataCell(Text(user['name'])),
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
                                              Text(user['role'].toUpperCase()),
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
                                                                          ) => const Center(
                                                                            child:
                                                                                CircularProgressIndicator(),
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
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
