import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Déclaration d'un paiement avec capture d'écran de l'envoi.
/// Pour un carnet, [caseAmount] et [maxCases] permettent de choisir le
/// nombre de cases payées.
class DeclarePaymentScreen extends StatefulWidget {
  const DeclarePaymentScreen({
    super.key,
    required this.title,
    required this.details,
    required this.onSubmit,
    this.fixedAmount,
    this.caseAmount,
    this.maxCases,
  });

  final String title;
  final List<(String, String)> details;
  final int? fixedAmount;
  final int? caseAmount;
  final int? maxCases;
  final Future<void> Function(String proofPath, int cases) onSubmit;

  @override
  State<DeclarePaymentScreen> createState() => _DeclarePaymentScreenState();
}

class _DeclarePaymentScreenState extends State<DeclarePaymentScreen> {
  XFile? _file;
  Uint8List? _preview;
  int _cases = 1;
  bool _busy = false;

  bool get _isCarnet => widget.caseAmount != null;

  int get _amount =>
      _isCarnet ? _cases * widget.caseAmount! : (widget.fixedAmount ?? 0);

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _file = file;
        _preview = bytes;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _submit() async {
    if (_file == null) {
      showInfo(context, 'Ajoutez la capture d\'écran de votre paiement');
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await Api.uploadProof(_file!);
      await widget.onSubmit(path, _cases);
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final (label, value) in widget.details)
                    InfoRow(label, value),
                  if (_isCarnet) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Text('Nombre de cases payées')),
                        IconButton.outlined(
                          onPressed: _cases > 1
                              ? () => setState(() => _cases--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '$_cases',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton.outlined(
                          onPressed: _cases < (widget.maxCases ?? 1)
                              ? () => setState(() => _cases++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 24),
                  InfoRow('Montant à payer', money(_amount), bold: true),
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
              _file == null
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

/// Le tontinier examine la preuve puis valide ou refuse (avec raison).
class ReviewPaymentScreen extends StatefulWidget {
  const ReviewPaymentScreen({
    super.key,
    required this.payment,
    required this.details,
    required this.canReview,
    required this.onReview,
  });

  final Payment payment;
  final List<(String, String)> details;
  final bool canReview;
  final Future<void> Function(bool approve, String? reason) onReview;

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
                          p.profile?.fullName ?? 'Membre',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusChip.payment(p.status),
                    ],
                  ),
                  if (p.profile != null) Text(p.profile!.phone),
                  const Divider(height: 24),
                  for (final (label, value) in widget.details)
                    InfoRow(label, value),
                  InfoRow('Montant', money(p.amount), bold: true),
                  InfoRow('Déclaré le', dateTime(p.declaredAt)),
                  if (p.status == PaymentStatus.rejected)
                    InfoRow('Raison du refus', p.rejectionReason ?? ''),
                ],
              ),
            ),
          ),
          const SectionTitle('Preuve de paiement'),
          ProofImage(p.proofPath, height: 420),
          const SizedBox(height: 4),
          Text(
            'Touchez l\'image pour l\'agrandir',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pending && widget.canReview) ...[
            const SizedBox(height: 24),
            Row(
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
          ],
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
