import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

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
    'REÇU DE PAIEMENT — $owner',
    'N° ${p.receiptNumber}',
    line,
    'Tontine : $tontine',
    item,
    'Payé par : ${p.payer.fullName} (${p.payer.phone})',
    'Détail : $detail',
    if (p.penalty > 0) 'Pénalités de retard : ${money(p.penalty)}',
    'Montant : ${money(p.amount)}',
    'Mode : ${methodLabel(p.method)}',
    if (p.recordedByOwner)
      'Encaissé par le tontinier le ${dateTime(p.reviewedAt ?? p.declaredAt)}'
    else ...[
      'Déclaré le ${dateTime(p.declaredAt)}',
      if (p.reviewedAt != null) 'Validé le ${dateTime(p.reviewedAt!)}',
    ],
    line,
    'Reçu COTIZI — paiement validé par le tontinier.',
  ].join('\n');
}

/// Numéros Mobile Money du tontinier, avec bouton « copier ».
class PaymentAccountsCard extends StatelessWidget {
  const PaymentAccountsCard({
    super.key,
    required this.accounts,
    required this.ownerName,
  });

  final List<PaymentAccount> accounts;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (accounts.isEmpty) {
      return Text(
        'Demandez à $ownerName son numéro Mobile Money.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final a in accounts)
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(
                a.number,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [a.operator, if (a.holder.isNotEmpty) a.holder].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Copier le numéro',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: a.number));
                  if (context.mounted) showInfo(context, 'Numéro copié');
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Choix du nombre de cotisations (ou de cases) payées.
class _UnitsPicker extends StatelessWidget {
  const _UnitsPicker({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton.outlined(
          tooltip: 'Moins',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Plus',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Déclaration d'un paiement par le client : nombre de cotisations (ou de
/// cases), mode (Mobile Money avec capture, ou espèces), pénalités.
class DeclarePaymentScreen extends StatefulWidget {
  const DeclarePaymentScreen({
    super.key,
    required this.title,
    required this.details,
    required this.onSubmit,
    required this.unitAmount,
    required this.maxUnits,
    required this.unitsLabel,
    required this.ownerName,
    this.accounts = const [],
    this.initialUnits = 1,
    this.penaltyFor,
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

  /// Tontinier et ses numéros Mobile Money.
  final String ownerName;
  final List<PaymentAccount> accounts;

  /// Pénalités de retard pour un nombre de cotisations payées.
  final int Function(int units)? penaltyFor;

  /// Message mis en avant (retard, avance…).
  final String? note;
  final Future<void> Function(
    int units,
    PaymentMethod method,
    Uint8List? proof,
    String? mime,
    String? note,
  )
  onSubmit;

  @override
  State<DeclarePaymentScreen> createState() => _DeclarePaymentScreenState();
}

class _DeclarePaymentScreenState extends State<DeclarePaymentScreen> {
  Uint8List? _preview;
  String _mime = 'image/jpeg';
  late int _units = widget.initialUnits.clamp(1, max(1, widget.maxUnits));
  PaymentMethod _method = PaymentMethod.mobileMoney;
  final _note = TextEditingController();
  bool _busy = false;

  int get _penalty => widget.penaltyFor?.call(_units) ?? 0;
  int get _amount => _units * widget.unitAmount + _penalty;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

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
    final cash = _method == PaymentMethod.cash;
    if (!cash && _preview == null) {
      showInfo(context, 'Ajoutez la capture d\'écran de votre paiement');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        _units,
        _method,
        cash ? null : _preview,
        cash ? null : _mime,
        _note.text,
      );
      if (!mounted) return;
      showInfo(
        context,
        cash
            ? 'Paiement déclaré. Le tontinier confirmera la réception de l\'argent.'
            : 'Paiement déclaré. En attente de validation du tontinier.',
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
    final cash = _method == PaymentMethod.cash;
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
                  _UnitsPicker(
                    label: widget.unitsLabel,
                    value: _units,
                    max: widget.maxUnits,
                    onChanged: (v) => setState(() => _units = v),
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    'Cotisations',
                    '$_units × ${money(widget.unitAmount)}',
                  ),
                  if (_penalty > 0)
                    InfoRow('Pénalités de retard', money(_penalty)),
                  InfoRow('Montant à payer', money(_amount), bold: true),
                ],
              ),
            ),
          ),
          const SectionTitle('Mode de paiement'),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(
                value: PaymentMethod.mobileMoney,
                icon: Icon(Icons.phone_android),
                label: Text('Mobile Money'),
              ),
              ButtonSegment(
                value: PaymentMethod.cash,
                icon: Icon(Icons.payments_outlined),
                label: Text('Espèces'),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 12),
          if (cash) ...[
            Text(
              'Remettez ${money(_amount)} en main propre à ${widget.ownerName}. '
              'Votre paiement sera validé quand il confirmera avoir reçu l\'argent.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Note (facultatif)',
                hintText: 'Ex. Remis au marché ce matin',
              ),
            ),
          ] else ...[
            Text(
              '1. Envoyez ${money(_amount)} à ${widget.ownerName} :',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            PaymentAccountsCard(
              accounts: widget.accounts,
              ownerName: widget.ownerName,
            ),
            const SizedBox(height: 12),
            Text(
              '2. Ajoutez la capture d\'écran de l\'envoi. Le tontinier la '
              'vérifiera avant de valider.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_preview != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _preview!,
                  height: 260,
                  fit: BoxFit.contain,
                ),
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
          ],
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

/// Le tontinier encaisse lui-même (espèces reçues, Mobile Money reçu sans
/// déclaration) : le paiement est validé d'office et un reçu est créé.
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.payerName,
    required this.details,
    required this.unitAmount,
    required this.maxUnits,
    required this.unitsLabel,
    required this.onSubmit,
    this.initialUnits = 1,
    this.penaltyFor,
  });

  final String payerName;
  final List<(String, String)> details;
  final int unitAmount;
  final int maxUnits;
  final String unitsLabel;
  final int initialUnits;
  final int Function(int units)? penaltyFor;

  /// Enregistre le paiement et renvoie le texte du reçu.
  final Future<String> Function(
    int units,
    PaymentMethod method,
    int penalty,
    String? note,
  )
  onSubmit;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  late int _units = widget.initialUnits.clamp(1, max(1, widget.maxUnits));
  PaymentMethod _method = PaymentMethod.cash;
  bool _applyPenalty = true;
  final _note = TextEditingController();
  bool _busy = false;

  int get _suggestedPenalty => widget.penaltyFor?.call(_units) ?? 0;
  int get _penalty => _applyPenalty ? _suggestedPenalty : 0;
  int get _amount => _units * widget.unitAmount + _penalty;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!await confirm(
      context,
      title: 'Encaisser',
      message:
          'Confirmez-vous avoir reçu ${money(_amount)} de ${widget.payerName} '
          '(${methodLabel(_method).toLowerCase()}) ?',
      confirmLabel: 'Oui, encaisser',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final receipt = await widget.onSubmit(
        _units,
        _method,
        _penalty,
        _note.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, size: 40),
          title: const Text('Paiement encaissé'),
          content: const Text(
            'Le paiement est validé. Envoyez le reçu au participant.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () {
                SharePlus.instance.share(ShareParams(text: receipt));
                Navigator.pop(context);
              },
              icon: const Icon(Icons.share),
              label: const Text('Envoyer le reçu'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encaisser un paiement')),
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
                  const Divider(height: 24),
                  _UnitsPicker(
                    label: widget.unitsLabel,
                    value: _units,
                    max: widget.maxUnits,
                    onChanged: (v) => setState(() => _units = v),
                  ),
                  if (_suggestedPenalty > 0)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Pénalités de retard : ${money(_suggestedPenalty)}',
                      ),
                      subtitle: const Text('Désactivez pour les annuler'),
                      value: _applyPenalty,
                      onChanged: (v) => setState(() => _applyPenalty = v),
                    ),
                  const Divider(height: 24),
                  InfoRow('Montant reçu', money(_amount), bold: true),
                ],
              ),
            ),
          ),
          const SectionTitle('Mode de paiement'),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(
                value: PaymentMethod.cash,
                icon: Icon(Icons.payments_outlined),
                label: Text('Espèces'),
              ),
              ButtonSegment(
                value: PaymentMethod.mobileMoney,
                icon: Icon(Icons.phone_android),
                label: Text('Mobile Money'),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (facultatif)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.check),
            label: Text('Encaisser ${money(_amount)}'),
          ),
        ],
      ),
    );
  }
}

/// Le tontinier examine le paiement puis valide ou refuse (avec raison).
/// Espèces : il confirme avoir reçu l'argent. Une fois validé, le reçu peut
/// être partagé.
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
    final cash = widget.payment.isCash;
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => _RejectDialog(cash: cash),
      );
      if (reason == null) return;
    } else if (!await confirm(
      context,
      title: cash ? 'Argent reçu' : 'Valider le paiement',
      message: cash
          ? 'Confirmez-vous avoir reçu ${money(widget.payment.amount)} en espèces ?'
          : 'Confirmez-vous avoir bien reçu ${money(widget.payment.amount)} ?',
      confirmLabel: cash ? 'Oui, reçu' : 'Valider',
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.isCash ? 'Paiement en espèces' : 'Paiement déclaré'),
      ),
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
                        label: Text(p.isCash ? 'Pas reçu' : 'Refuser'),
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
                        label: Text(p.isCash ? 'Argent reçu' : 'Valider'),
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StatusChip.payment(p.status),
                    ],
                  ),
                  Text(p.payer.phone),
                  const Divider(height: 24),
                  for (final (label, value) in widget.details)
                    InfoRow(label, value),
                  if (p.penalty > 0)
                    InfoRow('Pénalités de retard', money(p.penalty)),
                  InfoRow('Montant', money(p.amount), bold: true),
                  InfoRow('Mode', methodLabel(p.method)),
                  if (p.note != null) InfoRow('Note', p.note!),
                  if (p.recordedByOwner)
                    InfoRow(
                      'Encaissé par le tontinier',
                      dateTime(p.reviewedAt ?? p.declaredAt),
                    )
                  else ...[
                    InfoRow('Déclaré le', dateTime(p.declaredAt)),
                    if (p.reviewedAt != null)
                      InfoRow(
                        p.status == PaymentStatus.approved
                            ? 'Validé le'
                            : 'Refusé le',
                        dateTime(p.reviewedAt!),
                      ),
                  ],
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
          if (p.isCash || p.recordedByOwner || p.proofId.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                p.recordedByOwner
                    ? 'Paiement enregistré directement par le tontinier.'
                    : 'Paiement en espèces : pas de capture d\'écran. Le '
                          'tontinier confirme qu\'il a bien reçu l\'argent.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            const SectionTitle('Preuve de paiement'),
            ProofImage(p.proofId, height: 420),
            const SizedBox(height: 4),
            Text(
              'Touchez l\'image pour l\'agrandir',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.cash});

  final bool cash;

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
      title: Text(widget.cash ? 'Argent non reçu' : 'Refuser le paiement'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Raison',
          hintText: widget.cash
              ? 'Ex. Je n\'ai rien reçu, montant incomplet...'
              : 'Ex. Montant incorrect, capture illisible...',
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
