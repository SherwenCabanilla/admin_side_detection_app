import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/firebase_monitor.dart';
import 'dart:html' as html;

/// Banner that displays Firebase connection status
class FirebaseStatusBanner extends StatelessWidget {
  const FirebaseStatusBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FirebaseConnectionStatus>(
      stream: FirebaseMonitor().connectionStatus,
      initialData: FirebaseMonitor().currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? FirebaseConnectionStatus.connected;

        // Don't show banner if connected
        if (status == FirebaseConnectionStatus.connected) {
          return const SizedBox.shrink();
        }

        return _buildBanner(context, status);
      },
    );
  }

  Widget _buildBanner(BuildContext context, FirebaseConnectionStatus status) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String message;

    switch (status) {
      case FirebaseConnectionStatus.slow:
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade900;
        icon = Icons.warning_amber;
        message = 'Slow connection detected. Some features may be delayed.';
        break;
      case FirebaseConnectionStatus.disconnected:
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade900;
        icon = Icons.cloud_off;
        message = 'Connection to Firebase lost. Attempting to reconnect...';
        break;
      case FirebaseConnectionStatus.authError:
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade900;
        icon = Icons.error_outline;
        message = 'Authentication error. Please sign in again.';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Material(
      color: backgroundColor,
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                _showConnectionHelpDialog(context, status);
              },
              icon: Icon(Icons.help_outline, color: textColor, size: 18),
              label: Text(
                'Help',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                await FirebaseMonitor().checkConnection();
              },
              icon: Icon(Icons.refresh, color: textColor),
              tooltip: 'Retry connection',
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionHelpDialog(
    BuildContext context,
    FirebaseConnectionStatus status,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  status == FirebaseConnectionStatus.slow
                      ? Icons.warning_amber
                      : Icons.cloud_off,
                  color:
                      status == FirebaseConnectionStatus.slow
                          ? Colors.orange
                          : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text('Connection Issue'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status == FirebaseConnectionStatus.slow
                        ? 'The connection to Firebase is slow or unstable.'
                        : 'Unable to connect to Firebase servers.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This could be caused by:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletPoint('Firebase service outage or maintenance'),
                  _buildBulletPoint('Your internet connection is unstable'),
                  _buildBulletPoint('Network firewall blocking Firebase'),
                  _buildBulletPoint('DNS or routing issues'),
                  const SizedBox(height: 16),
                  const Text(
                    'What you can do:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletPoint(
                    'Check your internet connection',
                    Colors.green,
                  ),
                  _buildBulletPoint('Try refreshing the page', Colors.green),
                  _buildBulletPoint(
                    'Wait a few minutes and try again',
                    Colors.green,
                  ),
                  _buildBulletPoint('Check Firebase status page', Colors.green),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      // Direct way to open URL in new tab for web
                      if (kIsWeb) {
                        html.window.open(
                          'https://status.firebase.google.com/',
                          '_blank',
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check Firebase Status',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'status.firebase.google.com',
                                  style: TextStyle(
                                    color: Colors.blue.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await FirebaseMonitor().checkConnection();

                  // Show result
                  if (context.mounted) {
                    final newStatus = FirebaseMonitor().currentStatus;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          newStatus == FirebaseConnectionStatus.connected
                              ? '✓ Connection restored!'
                              : 'Still unable to connect. Please try again.',
                        ),
                        backgroundColor:
                            newStatus == FirebaseConnectionStatus.connected
                                ? Colors.green
                                : Colors.orange,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildBulletPoint(String text, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 16,
              color: color ?? Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(text, style: TextStyle(color: color ?? Colors.black87)),
          ),
        ],
      ),
    );
  }
}
