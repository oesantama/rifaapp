import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/url_helper.dart';

class EvidenceUrlViewerDialog extends StatefulWidget {
  final String url;

  const EvidenceUrlViewerDialog({super.key, required this.url});

  static void show(BuildContext context, String url) {
    if (url.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => EvidenceUrlViewerDialog(url: url.trim()),
    );
  }

  @override
  State<EvidenceUrlViewerDialog> createState() => _EvidenceUrlViewerDialogState();
}

class _EvidenceUrlViewerDialogState extends State<EvidenceUrlViewerDialog> {
  bool _imageError = false;

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.url.trim();
    final linkType = UrlHelper.getLinkType(rawUrl);
    final linkName = UrlHelper.getLinkTypeName(rawUrl);
    final directImageUrl = UrlHelper.getDirectImageUrl(rawUrl);

    IconData platformIcon = Icons.link;
    Color platformColor = AppTheme.primaryBlue;

    switch (linkType) {
      case 'google_drive':
        platformIcon = Icons.add_to_drive;
        platformColor = Colors.green.shade700;
        break;
      case 'google_photos':
        platformIcon = Icons.photo_library;
        platformColor = Colors.deepOrange.shade600;
        break;
      case 'onedrive':
        platformIcon = Icons.cloud;
        platformColor = Colors.blue.shade800;
        break;
      case 'dropbox':
        platformIcon = Icons.folder_shared;
        platformColor = Colors.indigo.shade600;
        break;
      case 'imgur':
        platformIcon = Icons.image;
        platformColor = AppTheme.secondaryEmerald;
        break;
      case 'direct_image':
        platformIcon = Icons.image_search;
        platformColor = Colors.teal.shade700;
        break;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: platformColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(platformIcon, color: platformColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Evidencia de Entrega de Premio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Enlace de $linkName',
                  style: TextStyle(fontSize: 12, color: platformColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // IMAGE PREVIEW OR FALLBACK CARD
            if (directImageUrl != null && !_imageError) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    directImageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 200,
                        color: Colors.grey.shade100,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _imageError = true);
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              // BRANDED CLOUD STORAGE CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: platformColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: platformColor.withOpacity(0.3), width: 1.5),
                ),
                child: Column(
                  children: [
                    Icon(platformIcon, size: 48, color: platformColor),
                    const SizedBox(height: 10),
                    Text(
                      'Documento / Enlace en $linkName',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: platformColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Este enlace redirige a un archivo almacenado en $linkName. Haz clic en el botón de abajo para abrirlo directamente en alta resolución.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // URL DISPLAY BOX
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      rawUrl,
                      style: const TextStyle(fontSize: 11, color: Colors.black87, fontFamily: 'monospace'),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await UrlHelper.copyToClipboard(rawUrl);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📋 Enlace copiado al portapapeles'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => UrlHelper.openUrl(rawUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Abrir en $linkName'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: platformColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class EvidencePreviewTile extends StatefulWidget {
  final String url;
  final bool compact;

  const EvidencePreviewTile({super.key, required this.url, this.compact = false});

  @override
  State<EvidencePreviewTile> createState() => _EvidencePreviewTileState();
}

class _EvidencePreviewTileState extends State<EvidencePreviewTile> {
  bool _imageError = false;

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.url.trim();
    if (rawUrl.isEmpty) return const SizedBox.shrink();

    final linkType = UrlHelper.getLinkType(rawUrl);
    final linkName = UrlHelper.getLinkTypeName(rawUrl);
    final directImageUrl = UrlHelper.getDirectImageUrl(rawUrl);

    IconData platformIcon = Icons.link;
    Color platformColor = AppTheme.primaryBlue;

    switch (linkType) {
      case 'google_drive':
        platformIcon = Icons.add_to_drive;
        platformColor = Colors.green.shade700;
        break;
      case 'google_photos':
        platformIcon = Icons.photo_library;
        platformColor = Colors.deepOrange.shade600;
        break;
      case 'onedrive':
        platformIcon = Icons.cloud;
        platformColor = Colors.blue.shade800;
        break;
      case 'dropbox':
        platformIcon = Icons.folder_shared;
        platformColor = Colors.indigo.shade600;
        break;
      case 'imgur':
        platformIcon = Icons.image;
        platformColor = AppTheme.secondaryEmerald;
        break;
      case 'direct_image':
        platformIcon = Icons.image_search;
        platformColor = Colors.teal.shade700;
        break;
    }

    return Card(
      elevation: 0,
      color: platformColor.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: platformColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(platformIcon, size: 18, color: platformColor),
                const SizedBox(width: 8),
                Text(
                  'Evidencia ($linkName)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: platformColor),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => UrlHelper.openUrl(rawUrl),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: platformColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.open_in_new, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Abrir Enlace',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (directImageUrl != null && !_imageError) ...[
              InkWell(
                onTap: () => EvidenceUrlViewerDialog.show(context, rawUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    directImageUrl,
                    height: widget.compact ? 100 : 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _imageError = true);
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ] else ...[
              InkWell(
                onTap: () => EvidenceUrlViewerDialog.show(context, rawUrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_red_eye, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ver detalles y foto en $linkName (${rawUrl.length > 35 ? "${rawUrl.substring(0, 35)}..." : rawUrl})',
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
