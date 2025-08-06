import 'package:flutter/material.dart';
import '../models/admin_user.dart';
import 'user_management.dart';
// import 'expert_management.dart';
import 'reports.dart';
import 'settings.dart';
import 'reports.dart' show DiseaseDistributionChart;
import '../models/user_store.dart';
import '../shared/total_users_card.dart';
import '../shared/pending_approvals_card.dart';
import '../services/scan_requests_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;

class AdminDashboard extends StatefulWidget {
  final AdminUser adminUser;
  const AdminDashboard({Key? key, required this.adminUser}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  // Real data for disease distribution and reports
  List<Map<String, dynamic>> _diseaseStats = [];
  List<Map<String, dynamic>> _reportsTrend = [];
  Map<String, dynamic> _stats = {
    'totalReportsReviewed': 0,
    'pendingRequests': 0,
    'averageResponseTime': '0 hours',
  };

  // Add selected time range for disease distribution
  String _selectedTimeRange = 'Last 7 Days';

  // Remove the hardcoded activities list
  // List<Map<String, dynamic>> activities = [
  //   {
  //     'icon': Icons.person_add,
  //     'action': 'Accepted new user registration',
  //     'user': 'John Doe',
  //     'time': '2 hours ago',
  //     'color': Colors.green,
  //   },
  //   {
  //     'icon': Icons.verified_user,
  //     'action': 'Verified expert account',
  //     'user': 'Dr. Smith',
  //     'time': '3 hours ago',
  //     'color': Colors.blue,
  //   },
  //   {
  //     'icon': Icons.block,
  //     'action': 'Rejected user registration',
  //     'user': 'Jane Smith',
  //     'time': '5 hours ago',
  //     'color': Colors.red,
  //   },
  //   {
  //     'icon': Icons.edit,
  //     'action': 'Updated user permissions',
  //     'user': 'Mike Johnson',
  //     'time': '1 day ago',
  //     'color': Colors.orange,
  //   },
  // ];

  Future<void> logActivity({
    required String action,
    required String user,
    required String type, // e.g., 'accept', 'delete'
    required Color color,
    required IconData icon,
  }) async {
    await cf.FirebaseFirestore.instance.collection('activities').add({
      'action': action,
      'user': user,
      'type': type,
      'color': color.value,
      'icon': icon.codePoint,
      'timestamp': cf.FieldValue.serverTimestamp(),
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all data in parallel
      await Future.wait([
        _loadUsers(),
        _loadStats(),
        _loadReportsTrend(),
        _loadDiseaseStats(),
      ]);
    } catch (e) {
      print('Error loading dashboard data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await UserStore.getUsers();
      setState(() {
        _users = users;
      });
    } catch (e) {
      print('Error loading users: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final completedReports =
          await ScanRequestsService.getCompletedReportsCount();
      final pendingReports = await ScanRequestsService.getPendingReportsCount();
      final averageResponseTime =
          await ScanRequestsService.getAverageResponseTime(
            timeRange: 'Last 7 Days',
          );

      setState(() {
        _stats['totalReportsReviewed'] = completedReports;
        _stats['pendingRequests'] = pendingReports;
        _stats['averageResponseTime'] = averageResponseTime;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _loadReportsTrend() async {
    try {
      final trend = await ScanRequestsService.getReportsTrend(
        timeRange: 'Last 7 Days',
      );
      setState(() {
        _reportsTrend = trend;
      });
    } catch (e) {
      print('Error loading reports trend: $e');
    }
  }

  Future<void> _loadDiseaseStats() async {
    try {
      final stats = await ScanRequestsService.getDiseaseStats(
        timeRange: _selectedTimeRange,
      );
      setState(() {
        _diseaseStats = stats;
      });
    } catch (e) {
      print('Error loading disease stats: $e');
    }
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${widget.adminUser.username}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Glad to see you back!',
                      style: TextStyle(fontSize: 18, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Dashboard',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stats Grid
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: 1.4,
                  children: [
                    TotalUsersCard(
                      onTap: () {
                        setState(() {
                          _selectedIndex = 1; // Switch to users tab
                        });
                      },
                    ),
                    GestureDetector(
                      onTap: () => _showPendingApprovalsDialog(context),
                      child: const PendingApprovalsCard(),
                    ),
                    // Replace TotalReportsCard with TotalReportsReviewedCard
                    TotalReportsReviewedCard(
                      totalReports: _stats['totalReportsReviewed'],
                      reportsTrend: _reportsTrend,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder:
                              (context) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Container(
                                  width:
                                      MediaQuery.of(context).size.width * 0.9,
                                  height:
                                      MediaQuery.of(context).size.height * 0.8,
                                  padding: const EdgeInsets.all(20),
                                  child: ReportsModalContent(),
                                ),
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Disease Distribution Chart
            DiseaseDistributionChart(
              diseaseStats: _diseaseStats,
              selectedTimeRange: _selectedTimeRange,
              onTimeRangeChanged: (String newTimeRange) {
                setState(() {
                  _selectedTimeRange = newTimeRange;
                });
                _loadDiseaseStats();
                _loadReportsTrend();
              },
            ),
            const SizedBox(height: 24),

            // Admin Activity Feed
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<cf.QuerySnapshot>(
                      stream:
                          cf.FirebaseFirestore.instance
                              .collection('activities')
                              .orderBy('timestamp', descending: true)
                              .limit(20)
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const CircularProgressIndicator();
                        final docs = snapshot.data!.docs;
                        return SizedBox(
                          height:
                              400, // Adjust this value to fit about 10 items
                          child: ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder:
                                (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final data =
                                  docs[index].data() as Map<String, dynamic>;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Color(data['color']),
                                  child: Icon(
                                    IconData(
                                      data['icon'],
                                      fontFamily: 'MaterialIcons',
                                    ),
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(data['action'] ?? ''),
                                subtitle: Text(
                                  '${data['user'] ?? ''} • '
                                  '${data['timestamp'] != null ? (data['timestamp'] as cf.Timestamp).toDate().toString() : ''}',
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    double? percentChange,
    bool? isUp,
    VoidCallback? onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return _buildDashboard();
      case 1:
        return const UserManagement();
      case 2:
        return Reports(
          onGoToUsers: () {
            setState(() {
              _selectedIndex = 1;
            });
          },
        );
      case 3:
        return Settings(
          onViewReports: () {
            setState(() {
              _selectedIndex = 2;
            });
          },
        );
      default:
        return _buildDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sidebarItems = [
      {'icon': Icons.dashboard, 'label': 'Dashboard'},
      {'icon': Icons.people, 'label': 'Users'},
      {'icon': Icons.assessment, 'label': 'Reports'},
      {'icon': Icons.settings, 'label': 'Settings'},
    ];
    int? hoveredIndex;
    return StatefulBuilder(
      builder: (context, setSidebarState) {
        return Scaffold(
          body: Row(
            children: [
              // Custom Sidebar
              Container(
                width: 220,
                color: const Color(0xFF2D7204),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Column(
                        children: [
                          Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Admin Panel',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Sidebar Items
                    ...List.generate(sidebarItems.length, (index) {
                      final selected = _selectedIndex == index;
                      final hovered = hoveredIndex == index;
                      Color bgColor = Colors.transparent;
                      Color fgColor = Colors.white;
                      FontWeight fontWeight = FontWeight.w500;
                      if (selected) {
                        bgColor = const Color.fromARGB(255, 200, 183, 25);
                        fontWeight = FontWeight.bold;
                      } else if (hovered) {
                        bgColor = const Color.fromARGB(180, 200, 183, 25);
                        fontWeight = FontWeight.w600;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6.0,
                          horizontal: 12.0,
                        ),
                        child: MouseRegion(
                          onEnter:
                              (_) =>
                                  setSidebarState(() => hoveredIndex = index),
                          onExit:
                              (_) => setSidebarState(() => hoveredIndex = null),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(32),
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 18,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    sidebarItems[index]['icon'] as IconData,
                                    color: fgColor,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    sidebarItems[index]['label'] as String,
                                    style: TextStyle(
                                      color: fgColor,
                                      fontSize: 16,
                                      fontWeight: fontWeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                  ],
                ),
              ),
              // Main Content
              Expanded(child: _getScreen(_selectedIndex)),
            ],
          ),
        );
      },
    );
  }

  void _showPendingApprovalsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            insetPadding: const EdgeInsets.all(32),
            child: SizedBox(
              width: 1150, // Increased width for full table visibility
              child: _PendingApprovalsTableModal(onAction: _loadUsers),
            ),
          ),
    );
  }
}

class _PendingApprovalsTableModal extends StatefulWidget {
  final VoidCallback onAction;
  const _PendingApprovalsTableModal({required this.onAction});
  @override
  State<_PendingApprovalsTableModal> createState() =>
      _PendingApprovalsTableModalState();
}

class _PendingApprovalsTableModalState
    extends State<_PendingApprovalsTableModal> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await UserStore.getUsers();
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendingUsers = _users.where((u) => u['status'] == 'pending').toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Approvals',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed:
                    pendingUsers.isEmpty
                        ? null
                        : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Accept All Pending Users'),
                                  content: const Text(
                                    'Are you sure you want to accept all pending users?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Accept All'),
                                    ),
                                  ],
                                ),
                          );
                          if (confirm == true) {
                            bool allSuccess = true;
                            for (var user in pendingUsers) {
                              final success = await UserStore.updateUserStatus(
                                user['id'],
                                'active',
                              );
                              if (!success) allSuccess = false;
                            }
                            await _loadUsers();
                            widget.onAction();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  allSuccess
                                      ? 'All pending users have been accepted'
                                      : 'Some users could not be accepted. Please check Firebase configuration.',
                                ),
                                backgroundColor:
                                    allSuccess ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        },
                child: const Text('Accept All'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed:
                    pendingUsers.isEmpty
                        ? null
                        : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Delete All Pending Users'),
                                  content: const Text(
                                    'Are you sure you want to delete all pending users? This cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Delete All'),
                                    ),
                                  ],
                                ),
                          );
                          if (confirm == true) {
                            bool allSuccess = true;
                            for (var user in pendingUsers) {
                              final success = await UserStore.deleteUser(
                                user['id'],
                              );
                              if (!success) allSuccess = false;
                            }
                            await _loadUsers();
                            widget.onAction();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  allSuccess
                                      ? 'All pending users have been deleted'
                                      : 'Some users could not be deleted. Please check Firebase configuration.',
                                ),
                                backgroundColor:
                                    allSuccess ? Colors.red : Colors.orange,
                              ),
                            );
                          }
                        },
                child: const Text('Delete All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Phone Number')),
                    DataColumn(label: Text('Address')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows:
                      pendingUsers
                          .map(
                            (user) => DataRow(
                              cells: [
                                DataCell(Text(user['name'])),
                                DataCell(Text(user['email'])),
                                DataCell(Text(user['phone'] ?? '')),
                                DataCell(Text(user['address'] ?? '')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      user['role'].toString().toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Accept'),
                                        onPressed: () async {
                                          final confirm = await showDialog<
                                            bool
                                          >(
                                            context: context,
                                            builder:
                                                (context) => AlertDialog(
                                                  title: const Text(
                                                    'Accept User',
                                                  ),
                                                  content: Text(
                                                    'Are you sure you want to accept ${user['name']}?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style:
                                                          ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.green,
                                                          ),
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'Accept',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                          );
                                          if (confirm == true) {
                                            await UserStore.updateUserStatus(
                                              user['id'],
                                              'active',
                                            );
                                            await cf.FirebaseFirestore.instance
                                                .collection('activities')
                                                .add({
                                                  'action': 'Accepted user',
                                                  'user': user['name'],
                                                  'type': 'accept',
                                                  'color': Colors.green.value,
                                                  'icon':
                                                      Icons
                                                          .person_add
                                                          .codePoint,
                                                  'timestamp':
                                                      cf.FieldValue.serverTimestamp(),
                                                });
                                            await _loadUsers();
                                            widget.onAction();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${user['name']} has been accepted',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Delete'),
                                        onPressed: () async {
                                          final confirm = await showDialog<
                                            bool
                                          >(
                                            context: context,
                                            builder:
                                                (context) => AlertDialog(
                                                  title: const Text(
                                                    'Delete User',
                                                  ),
                                                  content: Text(
                                                    'Are you sure you want to delete ${user['name']}? This cannot be undone.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style:
                                                          ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                      onPressed:
                                                          () => Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                          );
                                          if (confirm == true) {
                                            await UserStore.deleteUser(
                                              user['id'],
                                            );
                                            await _loadUsers();
                                            widget.onAction();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${user['name']} has been deleted',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
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
        ],
      ),
    );
  }
}
