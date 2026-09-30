import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
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

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<void> _loadBackupInfo() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$_baseUrl/backup')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        setState(() {
          _backupStats = jsonDecode(response.body);
        });
      }
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadBackupFile() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/backup')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dbData = data['database'];
        final jsonStr = jsonEncode(dbData);
        final bytes = utf8.encode(jsonStr);

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

        setState(() => _isRestoring = true);

        final response = await http
            .post(
              Uri.parse('$_baseUrl/backup/restore'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(backupJson),
            )
            .timeout(const Duration(seconds: 8));

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
          throw 'Respuesta del servidor: ${response.body}';
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

  @override
  Widget build(BuildContext context) {
    final stats = _backupStats?['stats'] as Map<String, dynamic>? ?? {};
    final fileSizeKb = stats['fileSizeBytes'] != null ? ((stats['fileSizeBytes'] as num) / 1024).toStringAsFixed(1) : 'N/A';
    final lastMod = stats['lastModified'] != null ? stats['lastModified'].toString().substring(0, 19).replaceAll('T', ' ') : 'Reciente';

    final isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMobile ? 'Respaldo de Base de Datos' : 'Respaldo y Copias de Seguridad (SuperAdmin)',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 20 : null,
                          ),
                    ),
                    Text(
                      'Gestión y validación exclusiva de copias de seguridad de la base de datos (data.json).',
                      style: TextStyle(color: Colors.grey[600], fontSize: isMobile ? 12 : 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.refresh),
                onPressed: _loadBackupInfo,
                tooltip: 'Actualizar Diagnóstico',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // HEALTH METRICS CARDS
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                _buildMetricCard(
                  title: 'Estado de Base de Datos',
                  value: 'ACTIVA (OK)',
                  subtitle: 'Archivo data.json ($fileSizeKb KB)',
                  icon: Icons.storage_rounded,
                  color: AppTheme.secondaryEmerald,
                ),
                _buildMetricCard(
                  title: 'Empresas Registradas',
                  value: '${stats['companiesCount'] ?? 1}',
                  subtitle: 'Grupos activos',
                  icon: Icons.apartment,
                  color: AppTheme.primaryBlue,
                ),
                _buildMetricCard(
                  title: 'Sorteos / Boletas',
                  value: '${stats['rafflesCount'] ?? 0} Sorteos',
                  subtitle: '${stats['ticketsCount'] ?? 0} Boletas en sistema',
                  icon: Icons.confirmation_number_outlined,
                  color: AppTheme.accentAmber,
                ),
              ];
              if (constraints.maxWidth < 700) {
                return Column(
                  children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList(),
                );
              }
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[2]),
                ],
              );
            },
          ),
          SizedBox(height: isMobile ? 12 : 24),

          // BACKUP ACTION CARD
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.backup_rounded, color: AppTheme.primaryBlue, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Acciones de Respaldo y Restauración',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Descarga una copia completa de la base de datos para custodia o restaura el sistema en un clic.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                  const Divider(height: 28),
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      for (final button in [
                        ElevatedButton.icon(
                          onPressed: _downloadBackupFile,
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: Text('Descargar Copia de Seguridad (.json)', textAlign: TextAlign.center),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isRestoring ? null : _restoreBackupFromFile,
                          icon: _isRestoring
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.upload_file_rounded, size: 20),
                          label: Text('Restaurar Base de Datos desde Archivo', textAlign: TextAlign.center),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondaryEmerald,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ])
                        SizedBox(width: isMobile ? double.infinity : null, child: button),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
