import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  final double minWidth;
  final double minHeight;
  final double mobileMinWidth;

  const ResponsiveWrapper({
    Key? key,
    required this.child,
    this.minWidth = 1245,
    this.minHeight = 600,
    this.mobileMinWidth = 800,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Get the actual screen size
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // Detect if this is likely a mobile device
        final isMobile = kIsWeb && (screenWidth < 1024 || screenHeight < 600);

        // Use different minimum width based on device type
        final effectiveMinWidth = isMobile ? mobileMinWidth : minWidth;
        final effectiveMinHeight = minHeight;

        // Check if screen is smaller than minimum requirements
        final needsWidthConstraint = screenWidth < effectiveMinWidth;
        final needsHeightConstraint = screenHeight < effectiveMinHeight;

        // If screen meets minimum requirements, return child as is
        if (!needsWidthConstraint && !needsHeightConstraint) {
          return child;
        }

        // Show a message for screens that are too small
        return Scaffold(
          backgroundColor: Colors.grey[100],
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.screen_rotation,
                    size: 64,
                    color: Colors.orange[600],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Screen Resolution Too Small',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This admin panel requires a minimum screen resolution of ${effectiveMinWidth.toInt()}x${effectiveMinHeight.toInt()} pixels.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current resolution: ${screenWidth.toInt()}x${screenHeight.toInt()} pixels',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.blue[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Please resize your browser window or use a larger screen',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final double minWidth;
  final double minHeight;
  final double mobileMinWidth;

  const ResponsiveScaffold({
    Key? key,
    required this.body,
    this.minWidth = 1245,
    this.minHeight = 600,
    this.mobileMinWidth = 800,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ResponsiveWrapper(
      minWidth: minWidth,
      minHeight: minHeight,
      mobileMinWidth: mobileMinWidth,
      child: body,
    );
  }
}
