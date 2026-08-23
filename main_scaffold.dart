import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

/// Root scaffold with a bottom Material 3 [NavigationBar] — the app's
/// four top-level surfaces:
///
///   0. Mapa       (existing MapScreen)
///   1. Pedaladas  (placeholder — real rides land in a follow-up commit)
///   2. Amigos     (placeholder — real friends land in a follow-up commit)
///   3. Perfil     (existing ProfileScreen)
///
/// Uses [IndexedStack] so switching tabs preserves each screen's state
/// (map camera, form drafts, scroll positions).
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const MapScreen(),
      const _ComingSoonTab(
        icon: Icons.directions_bike,
        title: 'Pedaladas em breve',
        subtitle:
            'Grave suas rotas, veja distância, tempo e velocidade — em breve.',
      ),
      const _ComingSoonTab(
        icon: Icons.people,
        title: 'Amigos em breve',
        subtitle:
            'Adicione amigos, envie distintivos e acompanhe as contribuições da galera — em breve.',
      ),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bike_outlined),
            selectedIcon: Icon(Icons.directions_bike),
            label: 'Pedaladas',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Amigos',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 72, color: scheme.primary),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
