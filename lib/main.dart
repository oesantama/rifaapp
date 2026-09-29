import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/core/theme.dart';
import 'data/repositories/raffle_repository.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';
import 'ui/features/auth/views/login_view.dart';
import 'ui/features/raffles/view_models/raffle_view_model.dart';
import 'ui/features/tickets/view_models/ticket_view_model.dart';
import 'ui/features/advisors/view_models/advisor_view_model.dart';
import 'ui/features/winners/view_models/winner_view_model.dart';

import 'ui/features/dashboard/dashboard_screen.dart';
import 'ui/features/tickets/views/ticket_grid_view.dart';
import 'ui/features/advisors/views/advisor_management_view.dart';
import 'ui/features/admin_cash/views/admin_cash_view.dart';
import 'ui/features/winners/views/winner_registration_view.dart';
import 'ui/features/company/views/company_management_view.dart';
import 'ui/features/backup/views/database_backup_view.dart';
import 'ui/features/raffles/views/raffle_create_dialog.dart';
import 'ui/features/raffles/views/raffle_edit_dialog.dart';
import 'ui/features/auth/views/admin_profile_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RifaApp());
}

class RifaApp extends StatefulWidget {
  const RifaApp({super.key});

  @override
  State<RifaApp> createState() => _RifaAppState();
}

class _RifaAppState extends State<RifaApp> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    final repository = RaffleRepository();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => RaffleViewModel(repository: repository)..loadRaffles()),
        ChangeNotifierProvider(create: (_) => TicketViewModel(repository: repository)..loadTickets()),
        ChangeNotifierProvider(create: (_) => AdvisorViewModel(repository: repository)..loadAdvisors()),
        ChangeNotifierProvider(create: (_) => WinnerViewModel(repository: repository)..loadWinners()),
      ],
      child: MaterialApp(
        title: 'Gestión de Rifas y Boletas Multiplataforma',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: Consumer<AuthViewModel>(
          builder: (context, authVM, _) {
            if (!authVM.isLoggedIn) {
              return const LoginView();
            }
            return MainShellScreen(
              isDarkMode: _isDarkMode,
              onToggleDarkMode: () => setState(() => _isDarkMode = !_isDarkMode),
            );
          },
        ),
      ),
    );
  }
}

class MainShellScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleDarkMode;

  const MainShellScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleDarkMode,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authVM = Provider.of<AuthViewModel>(context, listen: false);
      final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
      raffleVM.loadRaffles(advisorId: authVM.activeAdvisor?.id, isAsesor: authVM.isAsesor);
    });
  }

  @override
  Widget build(BuildContext context) {
    final raffleVM = Provider.of<RaffleViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);

    // Filter pages and destinations based on Role
    final List<Widget> pages = authVM.isSuperAdmin
        ? [
            const CompanyManagementView(),
            const DatabaseBackupView(),
          ]
        : authVM.isAdmin
            ? [
                DashboardScreen(onNavigateTab: (idx) => setState(() => _selectedIndex = idx)),
                const TicketGridView(),
                const AdvisorManagementView(),
                const AdminCashView(),
                const WinnerRegistrationView(),
              ]
            : [
                DashboardScreen(onNavigateTab: (idx) => setState(() => _selectedIndex = idx)),
                const TicketGridView(),
                const WinnerRegistrationView(),
              ];

    // Ensure selected index is valid
    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            return Row(
              children: [
                const Icon(Icons.confirmation_number, color: AppTheme.accentAmber),
                const SizedBox(width: 8),
                const Text('RIFA MASTER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 18)),
                const SizedBox(width: 12),
                if (!authVM.isSuperAdmin && raffleVM.raffles.isNotEmpty)
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              value: raffleVM.selectedRaffle?.id,
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              items: raffleVM.raffles.map((r) {
                                String statusTag = (authVM.isAdmin && r.status == 'INACTIVA') ? ' [🔴 INACTIVA]' : '';
                                return DropdownMenuItem(
                                  value: r.id,
                                  child: Text('${r.title}$statusTag', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final selected = raffleVM.raffles.firstWhere((r) => r.id == val);
                                  raffleVM.selectRaffle(selected);
                                  Provider.of<TicketViewModel>(context, listen: false).loadTickets(raffleId: val);
                                }
                              },
                            ),
                          ),
                        ),
                        if (authVM.isAdmin && raffleVM.selectedRaffle != null)
                          IconButton(
                            icon: const Icon(Icons.edit_note, color: Colors.white70, size: 20),
                            tooltip: 'Editar Sorteo Actual (Estado, Asesores, Boletas)',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => RaffleEditDialog(raffle: raffleVM.selectedRaffle!),
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                if (isWide) const Spacer(),

                // CENTER COMPANY BANNER BADGE
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: authVM.isSuperAdmin
                          ? [Colors.purple.shade900, Colors.purple.shade700]
                          : [Colors.blue.shade900, Colors.blue.shade700],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: authVM.isSuperAdmin ? Colors.purpleAccent : Colors.lightBlueAccent,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        authVM.isSuperAdmin ? Icons.domain_rounded : Icons.apartment_rounded,
                        color: Colors.amber.shade300,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        authVM.companyName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),

                if (isWide) const Spacer(),
              ],
            );
          },
        ),
        actions: [
          // Active User Badge (Clickable to edit profile)
          Tooltip(
            message: (authVM.isAdmin && !authVM.isSuperAdmin)
                ? 'Clic para Editar Mi Perfil Administrador'
                : (authVM.isSuperAdmin ? 'SuperAdministrador Master' : 'Usuario Asesor'),
            child: InkWell(
              onTap: () {
                if (authVM.isAdmin && !authVM.isSuperAdmin) {
                  showDialog(
                    context: context,
                    builder: (_) => const AdminProfileDialog(),
                  );
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: authVM.isSuperAdmin
                      ? Colors.purple.withValues(alpha: 0.2)
                      : (authVM.isAdmin ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: authVM.isSuperAdmin
                        ? Colors.purpleAccent
                        : (authVM.isAdmin ? Colors.amber : Colors.blue),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      authVM.isSuperAdmin
                          ? Icons.verified_user
                          : (authVM.isAdmin ? Icons.admin_panel_settings : Icons.person),
                      size: 16,
                      color: authVM.isSuperAdmin
                          ? Colors.purpleAccent
                          : (authVM.isAdmin ? Colors.amber : Colors.blue),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      authVM.isSuperAdmin
                          ? authVM.currentUserName
                          : (authVM.isAdmin
                              ? '${authVM.currentUserName} ✏️'
                              : '${authVM.currentUserName} (${authVM.currentUserCode})'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: authVM.isSuperAdmin
                            ? Colors.purpleAccent
                            : (authVM.isAdmin ? Colors.amber : Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleDarkMode,
            tooltip: 'Cambiar Modo Oscuro/Claro',
          ),

          if (authVM.isAdmin && !authVM.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const RaffleCreateDialog(),
                );
              },
              tooltip: 'Crear Nuevo Sorteo',
            ),

          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.dangerRose),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cerrar Sesión'),
                  content: const Text('¿Está seguro de que desea salir del sistema?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
                      onPressed: () {
                        Navigator.pop(ctx);
                        authVM.logout();
                      },
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Cerrar Sesión',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Navigation Rail for Desktop/Tablet
          if (MediaQuery.of(context).size.width >= 700)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
              labelType: NavigationRailLabelType.all,
              destinations: authVM.isSuperAdmin
                  ? const [
                      NavigationRailDestination(
                        icon: Icon(Icons.apartment_outlined),
                        selectedIcon: Icon(Icons.apartment),
                        label: Text('Empresas'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.backup_outlined),
                        selectedIcon: Icon(Icons.backup),
                        label: Text('Backup BD'),
                      ),
                    ]
                  : authVM.isAdmin
                      ? const [
                          NavigationRailDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            selectedIcon: Icon(Icons.dashboard),
                            label: Text('Dashboard'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.grid_on_outlined),
                            selectedIcon: Icon(Icons.grid_on),
                            label: Text('Boletas'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.people_outline),
                            selectedIcon: Icon(Icons.people),
                            label: Text('Asesores'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.point_of_sale_outlined),
                            selectedIcon: Icon(Icons.point_of_sale),
                            label: Text('Caja Admin'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.emoji_events_outlined),
                            selectedIcon: Icon(Icons.emoji_events),
                            label: Text('Ganadores'),
                          ),
                        ]
                      : const [
                          NavigationRailDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            selectedIcon: Icon(Icons.dashboard),
                            label: Text('Dashboard'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.grid_on_outlined),
                            selectedIcon: Icon(Icons.grid_on),
                            label: Text('Mis Boletas'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.emoji_events_outlined),
                            selectedIcon: Icon(Icons.emoji_events),
                            label: Text('Premios'),
                          ),
                        ],
            ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main Body
          Expanded(child: pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 700
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (idx) => setState(() => _selectedIndex = idx),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppTheme.primaryBlue,
              items: authVM.isSuperAdmin
                  ? const [
                      BottomNavigationBarItem(icon: Icon(Icons.apartment), label: 'Empresas'),
                      BottomNavigationBarItem(icon: Icon(Icons.backup), label: 'Backup BD'),
                    ]
                  : authVM.isAdmin
                      ? const [
                          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Inicio'),
                          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Boletas'),
                          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Asesores'),
                          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Caja'),
                          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Premios'),
                        ]
                      : const [
                          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Inicio'),
                          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Boletas'),
                          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Premios'),
                        ],
            )
          : null,
    );
  }
}
