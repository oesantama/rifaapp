import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/services/auth_http.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/file_saver_web.dart' if (dart.library.io) 'package:rifaapp/ui/core/utils/file_saver_stub.dart';

class DatabaseBackupView extends StatefulWidget {
  const DatabaseBackupView({super.key});

  @override
  State<DatabaseBackupView> createState() => _DatabaseBackupViewState();
}

class _DatabaseBackupViewState extends State<DatabaseBackupView> {
  late final String _baseUrl = ApiService().baseUrl;
  Map<String, dynamic>? _backupStats;
  bool _isLoading = true;
  bool _isRestoring = false;
  List<Map<String, dynamic>> _snapshots = [];

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<void> _loadBackupInfo() async {
    setState(() => _isLoading = true);
    try {
      final response = await authGet(Uri.parse('$_baseUrl/backup')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        setState(() {
          _backupStats = jsonDecode(response.body);
        });
      }
      final snaps = await authGet(Uri.parse('$_baseUrl/backup/snapshots')).timeout(const Duration(seconds: 10));
      if (snaps.statusCode == 200 && mounted) {
        setState(() => _snapshots = (jsonDecode(snaps.body) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadSnapshot(Map<String, dynamic> snapshot) async {
    try {
      final id = Uri.encodeComponent(snapshot['id'].toString());
      final response = await authGet(Uri.parse('$_baseUrl/backup/snapshots/$id/download')).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw ApiException.fromResponse(response);
      final date = DateTime.tryParse(snapshot['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      final filename = 'copia_automatica_${snapshot['reason']}_${DateFormat('yyyyMMdd_HHmmss').format(date)}.json';
      saveAndDownloadBytes(filename, response.bodyBytes, mimeType: 'application/json');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('No se pudo descargar la copia: $e')),
        );
      }
    }
  }

  Future<bool> _confirmRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar esta copia?'),
        content: const Text(
          'Todos los datos actuales serán reemplazados por los de la copia seleccionada.\n\n'
          'Antes de restaurar, el sistema guarda automáticamente una copia de los datos actuales, '
          'que podrá descargar en "Copias automáticas" si necesita deshacer el cambio.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentAmber, foregroundColor: Colors.black87),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, restaurar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _downloadBackupFile() async {
    try {
      final response = await authGet(Uri.parse('$_baseUrl/backup/download')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final filename = 'backup_rifamaster_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
        saveAndDownloadBytes(filename, bytes, mimeType: 'application/json');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.secondaryEmerald,
              content: Text('✓ Copia de seguridad "$filename" descargada exitosamente.'),
            ),
          );
        }
      } else {
        throw 'Error HTTP ${response.statusCode} al generar respaldo';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al descargar backup: $e')),
        );
      }
    }
  }

  Future<void> _restoreBackupFromFile() async {
    try {
      List<int>? bytes = await pickFileBytes(allowedExtensions: ['json']);
      if (bytes != null && bytes.isNotEmpty) {
        String jsonStr = utf8.decode(bytes);
        Map<String, dynamic> backupJson = jsonDecode(jsonStr);
        if (!await _confirmRestore()) return;

        setState(() => _isRestoring = true);

        final response = await authPost(
          Uri.parse('$_baseUrl/backup/restore'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(backupJson),
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          await _loadBackupInfo();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ ¡Base de Datos restaurada exitosamente desde la copia de seguridad!'),
              ),
            );
          }
        } else {
          throw ApiException.fromResponse(response);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al restaurar backup: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  String _formatSize(num? bytes) {
    if (bytes == null) return '—';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _formatDate(String? iso) {
    final date = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (date == null) return 'Sin registro';
    return DateFormat('dd/MM/yyyy • hh:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _backupStats?['stats'] as Map<String, dynamic>? ?? {};
    final isOnline = _backupStats != null;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadBackupInfo,
      child: ListView(
        padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusHero(stats, isOnline, isMobile),
                  if (_storageError != null) ...[
                    const SizedBox(height: 12),
                    _buildStorageWarning(_storageError!),
                  ],
                  const SizedBox(height: 20),
                  _buildSectionTitle('Contenido de la base de datos'),
                  const SizedBox(height: 10),
                  _buildStatsGrid(stats),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Acciones'),
                  const SizedBox(height: 10),
                  _buildActionTile(
                    icon: Icons.download_rounded,
                    color: AppTheme.primaryBlue,
                    title: 'Descargar copia de seguridad',
                    subtitle: 'Guarda un archivo .json con toda la información actual del sistema.',
                    onTap: _downloadBackupFile,
                  ),
                  const SizedBox(height: 10),
                  _buildActionTile(
                    icon: Icons.settings_backup_restore_rounded,
                    color: AppTheme.accentAmber,
                    title: 'Restaurar desde archivo',
                    subtitle: 'Reemplaza los datos actuales por los de una copia descargada previamente.',
                    onTap: _isRestoring ? null : _restoreBackupFromFile,
                    busy: _isRestoring,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Copias automáticas'),
                  const SizedBox(height: 4),
                  Text(
                    'Se crean solas cada día y antes de restaurar o limpiar la base. Descárguelas y restáurelas como cualquier copia.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  _buildSnapshotsList(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: isDark ? 0.12 : 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primaryBlue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Recomendación: descargue una copia antes de importar boletas, restaurar datos o realizar '
                            'cambios importantes, y guárdela en un lugar seguro (Drive, correo o USB).',
                            style: TextStyle(fontSize: 12, height: 1.4),
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
    );
  }

  Widget _buildStatusHero(Map<String, dynamic> stats, bool isOnline, bool isMobile) {
    final statusColor = isOnline ? AppTheme.secondaryEmerald : AppTheme.dangerRose;

    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1E3A8A).withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shield_outlined, color: AppTheme.brandGold, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Respaldo de datos',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Copias de seguridad del sistema',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isLoading ? null : _loadBackupInfo,
                tooltip: 'Actualizar',
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  isOnline ? 'Base de datos operativa' : 'Sin conexión con el servidor',
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildHeroFact(Icons.update_rounded, 'Último cambio', _formatDate(stats['lastModified']?.toString())),
              _buildHeroFact(Icons.sd_storage_outlined, 'Tamaño', _formatSize(stats['fileSizeBytes'] as num?)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroFact(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Colors.grey[600]),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    final items = [
      (Icons.apartment_rounded, 'Empresas', stats['companiesCount'], AppTheme.primaryBlue),
      (Icons.event_note_rounded, 'Sorteos', stats['rafflesCount'], Colors.purple),
      (Icons.confirmation_number_outlined, 'Boletas', stats['ticketsCount'], AppTheme.accentAmber),
      (Icons.people_alt_outlined, 'Asesores', stats['advisorsCount'], AppTheme.secondaryEmerald),
      (Icons.emoji_events_outlined, 'Ganadores', stats['winnersCount'], AppTheme.dangerRose),
    ];
    final number = NumberFormat.decimalPattern('es_CO');

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final perRow = constraints.maxWidth >= 700 ? 5 : (constraints.maxWidth >= 420 ? 3 : 2);
        final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < items.length; i++)
              SizedBox(
                // An odd last card takes the full row on phones
                width: (perRow == 2 && i == items.length - 1 && items.length.isOdd) ? constraints.maxWidth : width,
                child: _buildStatTile(items[i].$1, items[i].$2, items[i].$3, items[i].$4, number),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatTile(IconData icon, String label, Object? value, Color color, NumberFormat number) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value is num ? number.format(value) : '—',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.1),
                    ),
                  ),
                  Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? get _storageError {
    final storage = _backupStats?['storage'];
    if (storage is Map && storage['lastError'] != null) return storage['lastError'].toString();
    return null;
  }

  Widget _buildStorageWarning(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dangerRose.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppTheme.dangerRose),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Los últimos cambios aún no se han guardado en la nube. El sistema lo sigue intentando '
              'automáticamente; mientras tanto descargue una copia de seguridad.\nDetalle: $error',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  static const _snapshotLabels = {
    'daily': 'Copia diaria',
    'before_restore': 'Antes de restaurar',
    'before_reset': 'Antes de limpiar la base',
  };

  Widget _buildSnapshotsList() {
    if (_snapshots.isEmpty) {
      return Text('Aún no hay copias automáticas.', style: TextStyle(fontSize: 12, color: Colors.grey[600]));
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final snap in _snapshots.take(10))
            ListTile(
              dense: true,
              leading: Icon(
                snap['location'] == 'firestore' ? Icons.cloud_done_outlined : Icons.inventory_2_outlined,
                color: AppTheme.primaryBlue,
              ),
              title: Text(_snapshotLabels[snap['reason']] ?? snap['reason'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${_formatDate(snap['createdAt']?.toString())} • ${_formatSize(snap['bytes'] as num?)}'
                '${snap['location'] == 'firestore' ? ' • en la nube' : ''}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Descargar',
                onPressed: () => _downloadSnapshot(snap),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
