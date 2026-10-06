import 'ui/core/utils/url_launcher_helper.dart' as web_launcher;
import 'version.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:flutter/material.dart';
import 'ui/features/legal/legal_widgets.dart';
import 'package:provider/provider.dart';
import 'ui/core/theme.dart';
import 'ui/core/widgets/app_logo.dart';
import 'ui/core/widgets/monetization_banners.dart';
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
import 'ui/features/control/views/control_view.dart';
import 'ui/features/sale_channels/view_models/sale_channel_view_model.dart';
import 'ui/features/sale_channels/views/sale_channels_view.dart';
import 'ui/features/banks/view_models/bank_view_model.dart';
import 'ui/features/banks/views/banks_view.dart';
import 'ui/features/lotteries/view_models/lottery_view_model.dart';
import 'ui/features/lotteries/views/lotteries_view.dart';
import 'ui/features/monetization/app_config_view_model.dart';
import 'ui/features/monetization/monetization_view.dart';
import 'ui/features/admin_cash/view_models/cash_view_model.dart';
import 'ui/features/admin_cash/views/advisor_cash_view.dart';
import 'ui/features/raffles/views/raffle_create_dialog.dart';
import 'ui/features/auth/views/admin_profile_dialog.dart';
import 'ui/features/auth/views/change_password_dialog.dart';
import 'ui/core/utils/cache_helper.dart';

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
        // Data is loaded after login (MainShellScreen): before that the API rejects requests
        ChangeNotifierProvider(create: (_) => RaffleViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => TicketViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => AdvisorViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => WinnerViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => SaleChannelViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => BankViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => LotteryViewModel(repository: repository)),
        ChangeNotifierProvider(create: (_) => AppConfigViewModel(repository: repository)..load()),
        ChangeNotifierProvider(create: (_) => CashViewModel(repository: repository)),
      ],
      child: MaterialApp(
        title: 'Rifa Master',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: Consumer<AuthViewModel>(
          builder: (context, authVM, _) {
            if (authVM.isRestoringSession) {
              return const Scaffold(
                backgroundColor: Color(0xFF0F172A),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.amber),
                ),
              );
            }
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
  Timer? _updateTimer;
  bool _updateBannerShown = false;

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// True when [server] is a newer semantic version than [current] (e.g. 2.1.0 > 2.0.3).
  static bool _isNewer(String server, String current) {
    List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final a = parts(server), b = parts(current);
    for (int i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<void> _checkForUpdate() async {
    if (_updateBannerShown || !mounted) return;
    try {
      final info = await RaffleRepository().fetchServerInfo();
      final serverVersion = '${info['version'] ?? ''}';
      if (!mounted || serverVersion.isEmpty || !_isNewer(serverVersion, appVersion)) return;
      _updateBannerShown = true;
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          backgroundColor: const Color(0xFFFFF7ED),
          leading: const Icon(Icons.system_update, color: AppTheme.accentAmber),
          content: Text(
            kIsWeb
                ? 'Hay una nueva versión de Rifa Master (v$serverVersion). Recargue para usarla; usted tiene la v$appVersion.'
                : 'Hay una nueva versión de Rifa Master (v$serverVersion). Instale el APK actualizado; usted tiene la v$appVersion.',
            style: const TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Más tarde'),
            ),
            if (kIsWeb) ElevatedButton(onPressed: web_launcher.reloadPage, child: const Text('Recargar ahora')),
          ],
        ),
      );
    } catch (_) {
      // No connection: try again on the next check
    }
  }

  int _selectedIndex = 0;

  bool _passwordPromptOpen = false;

  /// Blocks the app until a default/assigned password is replaced.
  void _promptPasswordChangeIfRequired(AuthViewModel authVM) {
    if (!authVM.mustChangePassword || _passwordPromptOpen) return;
    _passwordPromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ChangePasswordDialog.show(context, required: true);
      _passwordPromptOpen = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSessionData());
    // Detects when the server was updated while this app/browser keeps an older version open
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    _updateTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _checkForUpdate();
      if (mounted) {
        final auth = Provider.of<AuthViewModel>(context, listen: false);
        auth.refreshActiveAdvisor();
        auth.refreshUser(); // plan / ads changed by the SuperAdmin
        Provider.of<AppConfigViewModel>(context, listen: false).load();
      }
    });
  }

  /// Loads everything the logged-in user sees, right after login or session restore.
  Future<void> _loadSessionData() async {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
    final advisorVM = Provider.of<AdvisorViewModel>(context, listen: false);
    final winnerVM = Provider.of<WinnerViewModel>(context, listen: false);

    // Never show data left over from a previous session
    raffleVM.reset();
    ticketVM.reset();
    advisorVM.reset();
    winnerVM.reset();
    final saleChannelVM = Provider.of<SaleChannelViewModel>(context, listen: false)..reset();
    final bankVM = Provider.of<BankViewModel>(context, listen: false)..reset();
    final lotteryVM = Provider.of<LotteryViewModel>(context, listen: false)..reset();

    // Advisors and winners do not depend on the selected raffle: load them in parallel
    final independent = Future.wait([
      advisorVM.loadAdvisors(),
      winnerVM.loadWinners(),
      saleChannelVM.load(),
      bankVM.load(),
      lotteryVM.load(),
      authVM.refreshActiveAdvisor(), // numbers assigned since the session was saved
    ]);
    await raffleVM.loadRaffles(advisorId: authVM.activeAdvisor?.id, isAsesor: authVM.isAsesor);
    await Future.wait([
      ticketVM.loadTickets(raffleId: raffleVM.selectedRaffle?.id),
      independent,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final raffleVM = Provider.of<RaffleViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);
    _promptPasswordChangeIfRequired(authVM);

    // Filter pages and destinations based on Role
    final List<Widget> pages = authVM.isSuperAdmin
        ? [
            const CompanyManagementView(),
            const DatabaseBackupView(),
            const SaleChannelsView(),
            const BanksView(),
            const LotteriesView(),
            const MonetizationView(),
          ]
        : authVM.isAdmin
            ? [
                DashboardScreen(onNavigateTab: (idx) => setState(() => _selectedIndex = idx)),
                const TicketGridView(),
                const AdvisorManagementView(),
                const AdminCashView(),
                const WinnerRegistrationView(),
                const ControlView(),
              ]
            : [
                DashboardScreen(onNavigateTab: (idx) => setState(() => _selectedIndex = idx)),
                const TicketGridView(),
                const AdvisorCashView(),
                const WinnerRegistrationView(),
              ];

    // Ensure selected index is valid
    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final showMobileContextBar = screenWidth < 700 && !authVM.isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        bottom: showMobileContextBar ? _buildMobileContextBar(context, authVM, raffleVM) : null,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final isMedium = constraints.maxWidth >= 480;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 28),
                const SizedBox(width: 8),
                Text(
                  isWide ? 'RIFA MASTER' : 'RIFA',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 16),
                ),
                if (isWide && !authVM.isSuperAdmin && raffleVM.raffles.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        value: raffleVM.selectedRaffle?.id,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                        items: raffleVM.raffles.map((r) {
                          String statusTag = (authVM.isAdmin && r.status == 'INACTIVA') ? ' [🔴]' : '';
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
                ],
                if (isWide) const Spacer(),
                if (isMedium && (isWide || authVM.isSuperAdmin)) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: authVM.isSuperAdmin
                            ? [Colors.purple.shade900, Colors.purple.shade700]
                            : [Colors.blue.shade900, Colors.blue.shade700],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: authVM.isSuperAdmin ? Colors.purpleAccent : Colors.lightBlueAccent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          authVM.isSuperAdmin ? Icons.domain_rounded : Icons.apartment_rounded,
                          color: Colors.amber.shade300,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          authVM.companyName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isWide) const Spacer(),
              ],
            );
          },
        ),
        actions: [
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final isMobile = screenWidth < 600;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => showAccountSheet(
                      context,
                      name: authVM.currentUserName,
                      isSuperAdmin: authVM.isSuperAdmin,
                      onProfile: () {
                        if (authVM.isAdmin || authVM.isSuperAdmin) {
                          showDialog(context: context, builder: (_) => const AdminProfileDialog());
                        } else {
                          ChangePasswordDialog.show(context);
                        }
                      },
                    ),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: authVM.isSuperAdmin
                            ? Colors.purple.withValues(alpha: 0.2)
                            : (authVM.isAdmin ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: authVM.isSuperAdmin ? Colors.purpleAccent : (authVM.isAdmin ? Colors.amber : Colors.blue),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            authVM.isSuperAdmin ? Icons.verified_user : (authVM.isAdmin ? Icons.admin_panel_settings : Icons.person),
                            size: 14,
                            color: authVM.isSuperAdmin ? Colors.purpleAccent : (authVM.isAdmin ? Colors.amber : Colors.blue),
                          ),
                          if (!isMobile) ...[
                            const SizedBox(width: 4),
                            Text(
                              authVM.isSuperAdmin
                                  ? authVM.currentUserName
                                  : (authVM.isAdmin ? authVM.currentUserName : authVM.currentUserName),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: authVM.isSuperAdmin ? Colors.purpleAccent : (authVM.isAdmin ? Colors.amber : Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.cleaning_services_rounded, size: 20, color: Colors.amber),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('🧹 Limpiando caché y recargando aplicación...')),
                      );
                      Future.delayed(const Duration(milliseconds: 300), () {
                        clearAppCacheAndReload();
                      });
                    },
                    tooltip: 'Limpiar caché de la aplicación y recargar',
                  ),
                  IconButton(
                    icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode, size: 20),
                    onPressed: widget.onToggleDarkMode,
                    tooltip: 'Modo Oscuro/Claro',
                  ),
                  if (authVM.isAdmin && !authVM.isSuperAdmin)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => const RaffleCreateDialog(),
                        );
                      },
                      tooltip: 'Crear Nuevo Sorteo',
                    ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppTheme.dangerRose, size: 20),
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
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
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
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('v$appVersion', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ),
                ),
              ),
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
                      NavigationRailDestination(
                        icon: Icon(Icons.campaign_outlined),
                        selectedIcon: Icon(Icons.campaign),
                        label: Text('Medios'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.account_balance_outlined),
                        selectedIcon: Icon(Icons.account_balance),
                        label: Text('Bancos'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.confirmation_number_outlined),
                        selectedIcon: Icon(Icons.confirmation_number),
                        label: Text('Loterías'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.workspace_premium_outlined),
                        selectedIcon: Icon(Icons.workspace_premium),
                        label: Text('Planes'),
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
                          NavigationRailDestination(
                            icon: Icon(Icons.fact_check_outlined),
                            selectedIcon: Icon(Icons.fact_check),
                            label: Text('Control'),
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
                            icon: Icon(Icons.account_balance_wallet_outlined),
                            selectedIcon: Icon(Icons.account_balance_wallet),
                            label: Text('Mi Caja'),
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
          Expanded(
            child: Column(
              children: [
                const DemoBannerWidget(),
                Expanded(child: pages[_selectedIndex]),
                const AdBannerWidget(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 700
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (idx) => setState(() => _selectedIndex = idx),
              items: authVM.isSuperAdmin
                  ? const [
                      BottomNavigationBarItem(icon: Icon(Icons.apartment), label: 'Empresas'),
                      BottomNavigationBarItem(icon: Icon(Icons.backup), label: 'Backup BD'),
                      BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Medios'),
                      BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Bancos'),
                      BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: 'Loterías'),
                      BottomNavigationBarItem(icon: Icon(Icons.workspace_premium), label: 'Planes'),
                    ]
                  : authVM.isAdmin
                      ? const [
                          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Inicio'),
                          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Boletas'),
                          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Asesores'),
                          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Caja'),
                          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Premios'),
                          BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: 'Control'),
                        ]
                      : const [
                          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Inicio'),
                          BottomNavigationBarItem(icon: Icon(Icons.grid_on), label: 'Boletas'),
                          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Mi Caja'),
                          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Premios'),
                        ],
            )
          : null,
    );
  }

  /// Compact bar shown under the AppBar on phones so the company and the
  /// active raffle selector stay reachable (on wide screens they live in the title).
  PreferredSizeWidget _buildMobileContextBar(BuildContext context, AuthViewModel authVM, RaffleViewModel raffleVM) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Row(
          children: [
            Icon(Icons.apartment_rounded, color: Colors.amber.shade300, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.3),
              child: Text(
                authVM.companyName.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: Colors.white24,
            ),
            const Icon(Icons.confirmation_number_outlined, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: raffleVM.raffles.isEmpty
                  ? const Text(
                      'Sin sorteos',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        value: raffleVM.selectedRaffle?.id,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
                        items: raffleVM.raffles.map((r) {
                          String statusTag = (authVM.isAdmin && r.status == 'INACTIVA') ? ' [🔴]' : '';
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
          ],
        ),
      ),
    );
  }
}
