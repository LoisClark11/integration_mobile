import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single continuous gradient block for the top of a page.
///
/// It merges what used to be an AppBar and a separate header block into
/// one gradient that fades from [Color(0xFFC25E7A)] at the very top to
/// [Color(0xFFF0A6B8)] at the bottom, so there is no visible color jump
/// between the toolbar and the header text.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.toolbarTitle,
    required this.headerTitle,
    required this.subtitle,
    this.icon = Icons.spa_rounded,
    this.actions = const [],
    this.showBackButton = false,
  });

  /// Small bold title shown in the toolbar row.
  final String toolbarTitle;

  /// Large title shown below the toolbar row.
  final String headerTitle;

  /// Supporting text shown below [headerTitle].
  final String subtitle;

  /// Icon displayed next to [toolbarTitle].
  final IconData icon;

  /// Extra buttons shown on the right side of the toolbar row.
  final List<Widget> actions;

  /// Whether to show a back arrow on the left side.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    // The header runs under the system status bar, so it claims white
    // icons for as long as any part of it is up there. Once the page
    // scrolls this layer out of the status bar's reach, the app-wide
    // dark default set in main() takes over, keeping the clock and
    // battery readable over the cream pages below.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),

      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, topInset + 14, 20, 28),

        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC25E7A), Color(0xFFF0A6B8)],
          ),
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toolbar row
            Row(
              children: [
                if (showBackButton) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),

                    padding: EdgeInsets.zero,

                    onPressed: () {
                      Navigator.of(context).maybePop();
                    },
                  ),

                  const SizedBox(width: 6),
                ],

                Container(
                  padding: const EdgeInsets.all(7),

                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),

                  child: Icon(icon, size: 22, color: Colors.white),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    toolbarTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),

                ...actions,
              ],
            ),

            const SizedBox(height: 22),

            // Header text
            Text(
              headerTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
