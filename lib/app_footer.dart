import 'package:flutter/material.dart';

/// Bottom navigation footer shared by the main app sections.
///
/// Keeps a single active section and reports taps upward so the parent
/// can swap the body without pushing new routes.
class AppFooter extends StatelessWidget {
  const AppFooter({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// Index of the currently visible section.
  final int currentIndex;

  /// Called with the index of the section the user tapped.
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),

      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFFCEBEF),

          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected =
                states.contains(WidgetState.selected);

            return TextStyle(
              fontSize: 12,
              fontWeight: isSelected
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFFC25E7A)
                  : Colors.grey,
            );
          }),

          iconTheme: WidgetStateProperty.resolveWith((states) {
            final isSelected =
                states.contains(WidgetState.selected);

            return IconThemeData(
              size: 24,
              color: isSelected
                  ? const Color(0xFFC25E7A)
                  : Colors.grey,
            );
          }),
        ),

        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,

          height: 68,

          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: "Products",
            ),

            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}