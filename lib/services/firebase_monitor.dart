import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Monitors Firebase connectivity and health status
class FirebaseMonitor {
  static final FirebaseMonitor _instance = FirebaseMonitor._internal();
  factory FirebaseMonitor() => _instance;
  FirebaseMonitor._internal();

  final _connectionStatusController =
      StreamController<FirebaseConnectionStatus>.broadcast();
  Stream<FirebaseConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  FirebaseConnectionStatus _currentStatus = FirebaseConnectionStatus.connected;
  FirebaseConnectionStatus get currentStatus => _currentStatus;

  Timer? _healthCheckTimer;
  bool _isChecking = false;
  int _consecutiveFailures = 0;
  DateTime? _lastSuccessfulCheck;
  DateTime? _lastFailureTime;

  /// Start monitoring Firebase connectivity
  void startMonitoring() {
    if (_healthCheckTimer != null && _healthCheckTimer!.isActive) {
      return; // Already monitoring
    }

    debugPrint('🔍 [Firebase Monitor] Starting connectivity monitoring...');

    // Initial check
    _checkConnection();

    // Check every 15 seconds (faster recovery detection)
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkConnection();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    debugPrint('🛑 [Firebase Monitor] Stopping connectivity monitoring...');
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Manually trigger a connection check
  Future<bool> checkConnection() async {
    return await _checkConnection();
  }

  Future<bool> _checkConnection() async {
    if (_isChecking)
      return _currentStatus == FirebaseConnectionStatus.connected;

    _isChecking = true;

    try {
      // Quick connectivity test - try to read from an existing collection
      // Using 'admins' collection which should always exist
      await FirebaseFirestore.instance
          .collection('admins')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException('Connection timeout'),
          );

      // Connection successful
      _consecutiveFailures = 0;
      _lastSuccessfulCheck = DateTime.now();

      if (_currentStatus != FirebaseConnectionStatus.connected) {
        debugPrint('✅ [Firebase Monitor] Connection restored!');
        _updateStatus(FirebaseConnectionStatus.connected);
      }

      _isChecking = false;
      return true;
    } on FirebaseException catch (e) {
      debugPrint(
        '❌ [Firebase Monitor] Firebase error: ${e.code} - ${e.message}',
      );
      _handleConnectionFailure(e.code);
      _isChecking = false;
      return false;
    } on TimeoutException catch (e) {
      debugPrint('⏱️ [Firebase Monitor] Connection timeout: $e');
      _handleConnectionFailure('timeout');
      _isChecking = false;
      return false;
    } catch (e) {
      debugPrint('❌ [Firebase Monitor] Unexpected error: $e');
      _handleConnectionFailure('unknown');
      _isChecking = false;
      return false;
    }
  }

  void _handleConnectionFailure(String errorCode) {
    _consecutiveFailures++;
    _lastFailureTime = DateTime.now();

    FirebaseConnectionStatus newStatus;

    if (errorCode == 'timeout' || errorCode == 'unavailable') {
      newStatus = FirebaseConnectionStatus.slow;
    } else if (errorCode == 'permission-denied' ||
        errorCode == 'unauthenticated') {
      newStatus = FirebaseConnectionStatus.authError;
    } else if (_consecutiveFailures >= 3) {
      newStatus = FirebaseConnectionStatus.disconnected;
    } else {
      newStatus = FirebaseConnectionStatus.slow;
    }

    if (_currentStatus != newStatus) {
      _updateStatus(newStatus);
    }
  }

  void _updateStatus(FirebaseConnectionStatus status) {
    _currentStatus = status;
    _connectionStatusController.add(status);

    switch (status) {
      case FirebaseConnectionStatus.connected:
        debugPrint('🟢 [Firebase Monitor] Status: CONNECTED');
        break;
      case FirebaseConnectionStatus.slow:
        debugPrint('🟡 [Firebase Monitor] Status: SLOW CONNECTION');
        break;
      case FirebaseConnectionStatus.disconnected:
        debugPrint('🔴 [Firebase Monitor] Status: DISCONNECTED');
        break;
      case FirebaseConnectionStatus.authError:
        debugPrint('🔴 [Firebase Monitor] Status: AUTHENTICATION ERROR');
        break;
    }
  }

  /// Get human-readable status message
  String getStatusMessage() {
    switch (_currentStatus) {
      case FirebaseConnectionStatus.connected:
        return 'Connected to Firebase';
      case FirebaseConnectionStatus.slow:
        return 'Slow connection detected';
      case FirebaseConnectionStatus.disconnected:
        return 'Firebase connection lost';
      case FirebaseConnectionStatus.authError:
        return 'Authentication error';
    }
  }

  /// Get detailed diagnostic info
  Map<String, dynamic> getDiagnostics() {
    return {
      'status': _currentStatus.toString(),
      'consecutiveFailures': _consecutiveFailures,
      'lastSuccessfulCheck': _lastSuccessfulCheck?.toIso8601String(),
      'lastFailureTime': _lastFailureTime?.toIso8601String(),
      'isMonitoring': _healthCheckTimer?.isActive ?? false,
    };
  }

  void dispose() {
    stopMonitoring();
    _connectionStatusController.close();
  }
}

enum FirebaseConnectionStatus { connected, slow, disconnected, authError }

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
