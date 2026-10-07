import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Déclaration d'un paiement avec capture d'écran de l'envoi : le payeur
/// choisit combien de cotisations (ou de cases) il paie en une fois.
class DeclarePaymentScreen extends StatefulWidget {
  const DeclarePaymentScreen({
    super.key,
    required this.title,
    required this.details,
    required this.onSubmit,
    required this.unitAmount,
    required this.maxUnits,
    required this.unitsLabel,
    this.initialUnits = 1,
    this.note,
  });

  final String title;
  final List<(String, String)> details;

  /// Montant d'une cotisation (ou d'une case).
  final int unitAmount;
  final int maxUnits;

  /// « Nombre de cotisations payées », « Nombre de cases payées ».
  final String unitsLabel;
  final int initialUnits;

  /// Message mis en avant (retard, avance…).
  final String? note;
  final Future<void> Function(Uint8List proof, String mime, int units) onSubmit;

  @override
  State<DeclarePaymentScreen> createState() => _DeclarePaymentScreenState();
}

class _DeclarePaymentScreenState extends State<DeclarePaymentScreen> {
  Uint8List? _preview;
  String _mime = 'image/jpeg';
  late int _units = widget.initialUnits.clamp(1, max(1, widget.maxUnits));
  bool _busy = false;

  int get _amount => _units * widget.unitAmount;

  Future<void> _pick() async {
    try {
      // Capture réduite et compressée : elle est stockée dans la base.
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 60,
      );
      if (file == null) return;
      final (bytes, mime) = await Api.readProof(file);
      setState(() {
        _preview = bytes;
        _mime = mime;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _submit() async {
    if (_preview == null) {
      showInfo(context, 'Ajoutez la capture d\'écran de votre paiement');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_preview!, _mime, _units);
      if (!mounted) return;
      showInfo(
        context,
        'Paiement déclaré. En attente de validation du tontinier.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.note != null)
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.note!,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final (label, value) in widget.details)
                    InfoRow(label, value),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(child: Text(widget.unitsLabel)),
                      IconButton.outlined(
                        tooltip: 'Moins',
                        onPressed: _units > 1
                            ? () => setState(() => _units--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_units',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Plus',
                        onPressed: _units < widget.maxUnits
                            ? () => setState(() => _units++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    'Montant à payer',
                    '$_units × ${money(widget.unitAmount)} = ${money(_amount)}',
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Preuve de paiement'),
          Text(
            'Ajoutez la capture d\'écran de votre envoi (Mobile Money, virement...). '
            'Le tontinier la vérifiera avant de valider.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_preview != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_preview!, height: 280, fit: BoxFit.contain),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.image_outlined),
            label: Text(
              _preview == null
                  ? 'Choisir la capture d\'écran'
                  : 'Changer la capture',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('Envoyer la déclaration'),
          ),
        ],
      ),
    );
  }
}

/// Reçu d'un paiement validé, à partager (WhatsApp, SMS…).
String receiptText(
  Payment p, {
  required String tontine,
  required String item,
  required String owner,
  required String detail,
}) {
  const line = '──────────────';
  return [
    'REÇU DE PAIEMENT — COTIZI',
    'N° ${p.receiptNumber}',
    line,
    'Tontine : $tontine',
    item,
    'Payé par : ${p.payer.fullName} (${p.payer.phone})',
    'Détail : $detail',
    'Montant : ${money(p.amount)}',
    'Déclaré le ${dateTime(p.declaredAt)}',
    if (p.reviewedAt != null) 'Validé le ${dateTime(p.reviewedAt!)}',
    'Tontinier : $owner',
    line,
    'Paiement validé par le tontinier dans COTIZI.',
  ].join('\n');
}

/// Le tontinier examine la preuve puis valide ou refuse (avec raison).
/// Une fois validé, le reçu peut être partagé.
class ReviewPaymentScreen extends StatefulWidget {
  const ReviewPaymentScreen({
    super.key,
    required this.payment,
    required this.details,
    required this.canReview,
    required this.onReview,
    this.receipt,
  });

  final Payment payment;
  final List<(String, String)> details;
  final bool canReview;
  final Future<void> Function(bool approve, String? reason) onReview;

  /// Texte du reçu (paiement validé).
  final String? receipt;

  @override
  State<ReviewPaymentScreen> createState() => _ReviewPaymentScreenState();
}

class _ReviewPaymentScreenState extends State<ReviewPaymentScreen> {
  bool _busy = false;

  Future<void> _review(bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _RejectDialog(),
      );
      if (reason == null) return;
    } else if (!await confirm(
      context,
      title: 'Valider le paiement',
      message:
          'Confirmez-vous avoir bien reçu ${money(widget.payment.amount)} ?',
      confirmLabel: 'Valider',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onReview(approve, reason);
      if (!mounted) return;
      showInfo(context, approve ? 'Paiement validé' : 'Paiement refusé');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final pending = p.status == PaymentStatus.pending;
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement déclaré')),
      // Boutons de décision toujours visibles en bas de l'écran
      bottomNavigationBar: pending && widget.canReview
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: paymentStatusColor(
                            PaymentStatus.rejected,
                          ),
                          minimumSize: const Size(64, 48),
                        ),
                        onPressed: _busy ? null : () => _review(false),
                        icon: const Icon(Icons.close),
                        label: const Text('Refuser'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: paymentStatusColor(
                            PaymentStatus.approved,
                          ),
                        ),
                        onPressed: _busy ? null : () => _review(true),
                        icon: const Icon(Icons.check),
                        label: const Text('Valider'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.payer.fullName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusChip.payment(p.status),
                    ],
                  ),
                  Text(p.payer.phone),
                  const Divider(height: 24),
                  for (final (label, value) in widget.details)
                    InfoRow(label, value),
                  InfoRow('Montant', money(p.amount), bold: true),
                  InfoRow('Déclaré le', dateTime(p.declaredAt)),
                  if (p.reviewedAt != null)
                    InfoRow(
                      p.status == PaymentStatus.approved
                          ? 'Validé le'
                          : 'Refusé le',
                      dateTime(p.reviewedAt!),
                    ),
                  if (p.status == PaymentStatus.rejected)
                    InfoRow('Raison du refus', p.rejectionReason ?? ''),
                ],
              ),
            ),
          ),
          if (p.status == PaymentStatus.approved && widget.receipt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: widget.receipt!),
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text('Partager le reçu n°${p.receiptNumber}'),
              ),
            ),
          const SectionTitle('Preuve de paiement'),
          ProofImage(p.proofId, height: 420),
          const SizedBox(height: 4),
          Text(
            'Touchez l\'image pour l\'agrandir',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refuser le paiement'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Raison du refus',
          hintText: 'Ex. Montant incorrect, capture illisible...',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Refuser'),
        ),
      ],
    );
  }
}
