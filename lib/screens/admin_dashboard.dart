import 'package:flutter/material.dart';
import '../models/admin_user.dart';
import 'user_management.dart';
// import 'expert_management.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'reports.dart';
import '../models/user_store.dart';
import '../shared/total_users_card.dart';
import '../shared/pending_approvals_card.dart';
import '../services/scan_requests_service.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings.dart' as admin_settings;

// --- Custom snapshot wrappers ---
class UsersSnapshot {
  final QuerySnapshot? snapshot;
  UsersSnapshot(this.snapshot);
}

class ScanRequestsSnapshot {
  final QuerySnapshot? snapshot;
  ScanRequestsSnapshot(this.snapshot);
}

class AdminDashboardWrapper extends StatelessWidget {
  final AdminUser adminUser;
  const AdminDashboardWrapper({Key? key, required this.adminUser})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<UsersSnapshot?>.value(
          value: FirebaseFirestore.instance
              .collection('users')
              .snapshots()
              .map((s) => UsersSnapshot(s)),
          initialData: null,
        ),
        StreamProvider<ScanRequestsSnapshot?>.value(
          value: FirebaseFirestore.instance
              .collection('scan_requests')
              .snapshots()
              .map((s) => ScanRequestsSnapshot(s)),
          initialData: null,
        ),
      ],
      child: AdminDashboard(adminUser: adminUser),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  final AdminUser adminUser;
  const AdminDashboard({Key? key, required this.adminUser}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with AutomaticKeepAliveClientMixin {
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

  // Dynamic admin name that updates from Firestore
  String _currentAdminName = '';

  // Helper function to format timestamp
  String _formatTimestamp(cf.Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  // Helper function to get IconData from icon code
  IconData _getIconFromCode(int iconCode) {
    switch (iconCode) {
      case 0xe3c9: // Icons.person_add.codePoint
        return Icons.person_add;
      case 0xe14b: // Icons.block.codePoint
        return Icons.block;
      case 0xe3c7: // Icons.verified_user.codePoint
        return Icons.verified_user;
      case 0xe3c8: // Icons.edit.codePoint
        return Icons.edit;
      case 0xe872: // Icons.delete.codePoint
        return Icons.delete;
      case 0xe3c6: // Icons.person.codePoint
        return Icons.person;
      case 0xe3c5: // Icons.pending_actions.codePoint
        return Icons.pending_actions;
      case 0xe3c4: // Icons.assignment_turned_in.codePoint
        return Icons.assignment_turned_in;
      case 0xe3c3: // Icons.timer.codePoint
        return Icons.timer;
      case 0xe3c2: // Icons.warning_amber.codePoint
        return Icons.warning_amber;
      default:
        return Icons.info; // Default icon
    }
  }

  // Resolve activity icon primarily by 'type' for consistency across platforms.
  // Falls back to stored 'icon' codepoint when available.
  IconData _resolveActivityIcon(Map<String, dynamic> data) {
    final String type = (data['type'] ?? '').toString();
    switch (type) {
      case 'accept':
        return Icons.person_add;
      case 'update':
        return Icons.edit;
      case 'delete':
        return Icons.block;
      case 'verify':
        return Icons.verified_user;
      case 'pending':
        return Icons.pending_actions;
      case 'complete':
        return Icons.assignment_turned_in;
      case 'export':
        return Icons.picture_as_pdf;
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'failed_login':
        return Icons.error;
      case 'settings_change':
        return Icons.settings;
      case 'profile_update':
        return Icons.person_outline;
      case 'password_change':
        return Icons.security;
      case 'report_change':
        return Icons.date_range;
      case 'dashboard_change':
        return Icons.dashboard;
    }
    final dynamic iconCode = data['icon'];
    if (iconCode is int) return _getIconFromCode(iconCode);
    return Icons.info;
  }

  // Resolve color with a sensible default if missing
  Color _resolveActivityColor(Map<String, dynamic> data) {
    final dynamic c = data['color'];
    if (c is int) return Color(c);
    switch ((data['type'] ?? '').toString()) {
      case 'accept':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return Colors.red;
      case 'pending':
        return Colors.amber;
      case 'login':
        return Colors.green;
      case 'logout':
        return Colors.orange;
      case 'failed_login':
        return Colors.red;
      case 'settings_change':
        return Colors.blue;
      case 'profile_update':
        return Colors.purple;
      case 'password_change':
        return Colors.amber;
      case 'report_change':
        return Colors.indigo;
      case 'dashboard_change':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

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
    _currentAdminName =
        widget.adminUser.username; // Initialize with current name
    _loadData();
    _listenToAdminNameChanges(); // Listen for real-time updates
  }

  // Listen for real-time admin name changes
  void _listenToAdminNameChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      cf.FirebaseFirestore.instance
          .collection('admins')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && mounted) {
              final data = snapshot.data() as Map<String, dynamic>?;
              final newAdminName =
                  data?['adminName'] ?? widget.adminUser.username;
              if (newAdminName != _currentAdminName) {
                setState(() {
                  _currentAdminName = newAdminName;
                });
              }
            }
          });
    }
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
                      'Welcome, ${_currentAdminName.isNotEmpty ? _currentAdminName : widget.adminUser.username}',
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
                    const PendingApprovalsCard(),
                    // Replace TotalReportsCard with TotalReportsReviewedCard
                    TotalReportsReviewedCard(
                      totalReports: _stats['totalReportsReviewed'],
                      reportsTrend: _reportsTrend,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            final ValueNotifier<bool> fullscreen =
                                ValueNotifier<bool>(false);
                            return ValueListenableBuilder<bool>(
                              valueListenable: fullscreen,
                              builder:
                                  (context, isFull, _) => Dialog(
                                    insetPadding:
                                        isFull
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.symmetric(
                                              horizontal: 40,
                                              vertical: 40,
                                            ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          isFull
                                              ? BorderRadius.zero
                                              : BorderRadius.circular(16),
                                    ),
                                    child: Container(
                                      width:
                                          isFull
                                              ? MediaQuery.of(
                                                context,
                                              ).size.width
                                              : MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.9,
                                      height:
                                          isFull
                                              ? MediaQuery.of(
                                                context,
                                              ).size.height
                                              : MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.8,
                                      padding: const EdgeInsets.all(20),
                                      child: ReportsModalContent(
                                        fullscreenNotifier: fullscreen,
                                      ),
                                    ),
                                  ),
                            );
                          },
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
              onTimeRangeChanged: (String newTimeRange) async {
                // Log dashboard time range change
                try {
                  await cf.FirebaseFirestore.instance.collection('activities').add({
                    'action':
                        'Dashboard time range changed to ${_formatTimeRangeForActivity(newTimeRange)}',
                    'user':
                        _currentAdminName.isNotEmpty
                            ? _currentAdminName
                            : (widget.adminUser.username.isNotEmpty
                                ? widget.adminUser.username
                                : 'Admin'),
                    'type': 'dashboard_change',
                    'color': Colors.teal.value,
                    'icon': Icons.dashboard.codePoint,
                    'timestamp': cf.FieldValue.serverTimestamp(),
                  });
                } catch (e) {
                  print('Failed to log dashboard time range change: $e');
                }

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
                                  backgroundColor: _resolveActivityColor(data),
                                  child: Icon(
                                    _resolveActivityIcon(data),
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(data['action'] ?? ''),
                                subtitle: Text(
                                  '${data['user'] ?? ''} • '
                                  '${_formatTimestamp(data['timestamp'] as cf.Timestamp)}',
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
        return admin_settings.Settings(
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

  String _formatTimeRangeForActivity(String range) {
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          String fmt(DateTime d) {
            const months = [
              '',
              'Jan',
              'Feb',
              'Mar',
              'Apr',
              'May',
              'Jun',
              'Jul',
              'Aug',
              'Sep',
              'Oct',
              'Nov',
              'Dec',
            ];
            return '${months[d.month]} ${d.day}, ${d.year}';
          }

          return '"${fmt(s)} to ${fmt(e)}"';
        } catch (_) {}
      }
    }
    return '"$range"';
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Important for AutomaticKeepAliveClientMixin
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
}
