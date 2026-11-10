import 'package:flutter/material.dart';

/// Valida el formulario; si algo falla, lleva la vista al primer campo con error, le da el foco y avisa cuál es.
/// Devuelve true si todo está correcto.
bool validateAndFocus(BuildContext context, GlobalKey<FormState> formKey) {
  final form = formKey.currentState;
  if (form == null) return true;
  if (form.validate()) return true;

  FormFieldState? first;
  void visit(Element el) {
    if (first != null) return;
    if (el is StatefulElement && el.state is FormFieldState) {
      final st = el.state as FormFieldState;
      if (st.hasError) {
        first = st;
        return;
      }
    }
    el.visitChildren(visit);
  }

  (formKey.currentContext as Element?)?.visitChildren(visit);
  final field = first;
  if (field != null) {
    final fieldContext = field.context;
    Scrollable.ensureVisible(fieldContext, alignment: 0.2, duration: const Duration(milliseconds: 250));
    FocusNode? node;
    void findNode(Element el) {
      if (node != null) return;
      if (el.widget is EditableText) {
        node = (el.widget as EditableText).focusNode;
        return;
      }
      el.visitChildren(findNode);
    }

    (fieldContext as Element).visitChildren(findNode);
    node?.requestFocus();
    final msg = field.errorText ?? 'Revise los campos obligatorios';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('⚠️ Falta o es inválido: $msg')));
  }
  return false;
}
