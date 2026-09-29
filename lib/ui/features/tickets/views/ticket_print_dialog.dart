import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'dart:html' if (dart.library.io) 'file_saver_stub.dart' as html_shim;

class TicketPrintDialog extends StatefulWidget {
  final Ticket ticket;
  final String raffleTitle;

  const TicketPrintDialog({
    super.key,
    required this.ticket,
    required this.raffleTitle,
  });

  @override
  State<TicketPrintDialog> createState() => _TicketPrintDialogState();
}

class _TicketPrintDialogState extends State<TicketPrintDialog> {
  Color _themeColor = AppTheme.primaryBlue;
  String? _bgImageBase64;
  bool _showTalonario = true;

  void _pickBgImage() async {
    try {
      String? imageStr = await pickImageBase64();
      if (imageStr != null) {
        setState(() {
          _bgImageBase64 = imageStr;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.secondaryEmerald,
              content: Text('✓ Imagen de plantilla / diseño de boleta cargada con éxito.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al cargar imagen: $e')),
        );
      }
    }
  }

  void _triggerPrint() {
    try {
      // ignore: undefined_prefix_name
      html_shim.window.print();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para imprimir, presione Ctrl+P en su navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    ImageProvider? bgDecorationImage;
    if (_bgImageBase64 != null) {
      if (_bgImageBase64!.startsWith('data:image')) {
        String base64Content = _bgImageBase64!.split(',').last;
        bgDecorationImage = MemoryImage(base64Decode(base64Content));
      } else {
        bgDecorationImage = NetworkImage(_bgImageBase64!);
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // HEADER DIALOG
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.print, color: _themeColor, size: 28),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Impresión de Boleta - N° ${widget.ticket.ticketNumber}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Diseño con Talonario de Control y espacio para plantilla personalizada del administrador.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _triggerPrint,
                        icon: const Icon(Icons.print),
                        label: const Text('IMPRIMIR'),
                        style: ElevatedButton.styleFrom(backgroundColor: _themeColor),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  )
                ],
              ),
              const Divider(height: 20),

              // BARRA DE HERRAMIENTAS DE DISEÑO
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickBgImage,
                    icon: const Icon(Icons.image, size: 16),
                    label: Text(_bgImageBase64 == null ? 'Subir Diseño/Fondo de Boleta' : 'Cambiar Imagen de Fondo'),
                  ),
                  if (_bgImageBase64 != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _bgImageBase64 = null),
                      icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                      label: const Text('Quitar Fondo', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      const Text('Mostrar Talonario:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Switch(
                        value: _showTalonario,
                        activeColor: _themeColor,
                        onChanged: (val) => setState(() => _showTalonario = val),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 14),

              // CANVAS IMPRESO DE LA BOLETA
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _themeColor.withOpacity(0.4), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    )
                  ],
                  image: bgDecorationImage != null
                      ? DecorationImage(
                          image: bgDecorationImage,
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.white.withOpacity(0.82),
                            BlendMode.lighten,
                          ),
                        )
                      : null,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // TALONARIO / STUB DE CONTROL (IZQUIERDA)
                      if (_showTalonario)
                        Container(
                          width: 230,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: bgDecorationImage != null ? Colors.white.withOpacity(0.7) : Colors.grey.shade50,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                            ),
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade400, width: 2, style: BorderStyle.solid),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _themeColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'TALONARIO DE CONTROL',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _themeColor, letterSpacing: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'BOLETA N° ${widget.ticket.ticketNumber.toString().padLeft(4, '0')}',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _themeColor),
                                  ),
                                  const Divider(height: 14),
                                  const Text('Comprador:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    widget.ticket.buyerName.isNotEmpty ? widget.ticket.buyerName : 'Pendiente',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Teléfono:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    widget.ticket.buyerPhone.isNotEmpty ? widget.ticket.buyerPhone : 'N/A',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Vendedor / Asesor:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    widget.ticket.advisorName.isNotEmpty ? widget.ticket.advisorName : 'Admin',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Monto Abonado:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                  Text(
                                    currency.format(widget.ticket.totalPaid),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 35,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Firma / Sello Recibido',
                                      style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),

                      // BOLETA PRINCIPAL PARA EL COMPRADOR (DERECHA)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          color: bgDecorationImage != null ? Colors.white.withOpacity(0.65) : Colors.transparent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.raffleTitle.toUpperCase(),
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _themeColor),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'COMPROBANTE OFICIAL DE BOLETA',
                                          style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _themeColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'N° ${widget.ticket.ticketNumber.toString().padLeft(4, '0')}',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  )
                                ],
                              ),
                              const Divider(height: 20),

                              // NÚMEROS DE OPORTUNIDAD
                              Text(
                                'NÚMEROS DE OPORTUNIDAD (${widget.ticket.numbers.length} NÚMEROS):',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: widget.ticket.numbers.map((numStr) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _themeColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _themeColor.withOpacity(0.5), width: 1.5),
                                    ),
                                    child: Text(
                                      numStr,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                        color: _themeColor,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                              const SizedBox(height: 16),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Valor Boleta:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                      Text(
                                        currency.format(widget.ticket.price),
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Total Abonado:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                      Text(
                                        currency.format(widget.ticket.totalPaid),
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Saldo Pendiente:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                      Text(
                                        currency.format(widget.ticket.balancePending),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: widget.ticket.balancePending > 0 ? AppTheme.dangerRose : AppTheme.secondaryEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              const Divider(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('¡Gracias por tu compra y buena suerte! 🍀', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                                  Text(
                                    'Estado: ${AppTheme.getStatusLabel(widget.ticket.status)}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _themeColor),
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
