import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';
import '../reports.dart';
import '../widgets/common.dart';
import 'payment_screens.dart';

/// Paiement d'un carnet ouvert par le tontinier (validation) ou par le
/// client (consultation, reçu).
Widget carnetPaymentScreen(
  Carnet c,
  Payment p, {
  required bool canReview,
  Business? business,
}) => ReviewPaymentScreen(
  payment: p,
  canReview: canReview,
  details: [('Carnet', c.label), ('Cases payées', '${p.caseCount}')],
  onReview: (approve, reason) =>
      Api.reviewCarnetPayment(c.id, p, approve, reason),
  receipt: carnetReceipt(c, p, business),
);

String carnetReceipt(Carnet c, Payment p, Business? business) => receiptText(
  p,
  tontine: c.tontineName,
  item: 'Carnet : ${c.label}',
  owner: business?.name ?? c.ownerName,
  detail: '${p.caseCount} case(s) × ${money(c.caseAmount)}',
);

/// Détail d'un carnet de 31 cases, vu par le tontinier ou par le client.
class CarnetScreen extends StatefulWidget {
  const CarnetScreen({super.key, required this.carnetId});

  final String carnetId;

  @override
  State<CarnetScreen> createState() => _CarnetScreenState();
}

class _CarnetScreenState extends State<CarnetScreen> {
  late Future<(Carnet, List<Payment>)> _data = _load();
  Business? _business;

  Future<(Carnet, List<Payment>)> _load() async {
    final carnet = await Api.carnet(widget.carnetId);
    final results = await Future.wait([
      Api.carnetPayments(carnet),
      Api.business(carnet.ownerId),
    ]);
    _business = results[1] as Business?;
    return (carnet, results[0] as List<Payment>);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
  }

  void _openPayment(Carnet c, Payment p, bool isOwner) =>
      _push(carnetPaymentScreen(c, p, canReview: isOwner, business: _business));

  void _declare(Carnet c) => _push(
    DeclarePaymentScreen(
      title: 'Déclarer un paiement',
      unitAmount: c.caseAmount,
      maxUnits: c.remainingCases,
      unitsLabel: 'Nombre de cases payées',
      ownerName: _business?.name ?? c.ownerName,
      accounts: _business?.accounts ?? const [],
      details: [
        ('Carnet', c.label),
        ('Montant par case', money(c.caseAmount)),
        ('Cases restantes', '${c.remainingCases}'),
      ],
      onSubmit: (cases, method, proof, mime, note, reference) =>
          Api.declareCarnetPayment(
            carnet: c,
            caseCount: cases,
            method: method,
            proof: proof,
            mime: mime,
            note: note,
            reference: reference,
          ),
    ),
  );

  Future<void> _statement(Carnet c, List<Payment> payments) async {
    try {
      await shareCarnetStatement(
        carnet: c,
        payments: payments,
        business: _business,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carnet')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureView<(Carnet, List<Payment>)>(
          future: _data,
          onRetry: _reload,
          builder: (context, data) {
            final (c, payments) = data;
            final isOwner = c.ownerId == Api.uid;
            final pending = payments.where(
              (p) => p.status == PaymentStatus.pending,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(c, isOwner),
                if (isOwner && c.clientId == null) ...[
                  const SizedBox(height: 8),
                  InviteCodeCard(
                    code: c.inviteCode,
                    hint: 'Appuyez sur Partager : votre client recevra un lien pour rejoindre ce carnet.',
                    shareText: inviteMessage(
                      'Rejoins ton carnet « ${c.label} » '
                      '(${money(c.caseAmount)} par case) sur COTIZI.',
                      c.inviteCode,
                    ),
                  ),
                ],
                if (c.isClosed)
                  _closedBanner(c, isOwner)
                else if (c.refundRequested)
                  _refundBanner(c, isOwner)
                else if (c.isComplete)
                  _completeBanner(c, isOwner),
                if (isOwner && c.canClose) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _close(c),
                    icon: const Icon(Icons.task_alt),
                    label: Text(
                      c.refundRequested
                          ? 'Cotisations remboursées · clôturer'
                          : 'Carnet remis · clôturer',
                    ),
                  ),
                ],
                if (!isOwner && c.isActive && c.remainingCases > 0) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _declare(c),
                    icon: const Icon(Icons.upload),
                    label: const Text('Déclarer un paiement'),
                  ),
                ],
                if (!isOwner && c.isActive && !c.isComplete) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _askRefund(c),
                    icon: const Icon(Icons.undo),
                    label: const Text('Demander le remboursement'),
                  ),
                ],
                if (c.clientId != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _statement(c, payments),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Relevé PDF du carnet'),
                  ),
                ],
                const SectionTitle('Cases'),
                _CasesGrid(carnet: c),
                const SizedBox(height: 8),
                const _Legend(),
                if (isOwner && pending.isNotEmpty) ...[
                  SectionTitle('Paiements à valider (${pending.length})'),
                  for (final p in pending) _paymentTile(c, p, isOwner),
                ],
                SectionTitle('Historique des paiements'),
                if (payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Aucun paiement déclaré pour le moment.'),
                  ),
                for (final p in payments) _paymentTile(c, p, isOwner),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Carnet c, bool isOwner) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.label,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              isOwner
                  ? c.tontineName
                  : '${c.tontineName} · Tontinier : ${c.ownerName}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            if (isOwner)
              InfoRow(
                'Client',
                c.client == null
                    ? 'Pas encore de client'
                    : '${c.client!.fullName} · ${c.client!.phone}',
              ),
            InfoRow('Montant par case', money(c.caseAmount)),
            InfoRow('Cases payées', '${c.approvedCases} / ${c.caseCount}'),
            if (c.pendingCases > 0)
              InfoRow('En attente de validation', '${c.pendingCases} case(s)'),
            InfoRow('Montant validé', money(c.approvedCases * c.caseAmount)),
            InfoRow(
              'Le client reçoit (30 cases)',
              money(c.clientPayout),
              bold: true,
            ),
            InfoRow('Commission (dernière case)', money(c.caseAmount)),
          ],
        ),
      ),
    );
  }

  /// Le client arrête son carnet : cases payées moins une (commission).
  Future<void> _askRefund(Carnet c) async {
    if (c.pendingCases > 0) {
      showInfo(
        context,
        'Attendez que le tontinier valide vos paiements en attente.',
      );
      return;
    }
    if (c.approvedCases == 0) {
      showInfo(context, 'Aucune case payée : rien à rembourser.');
      return;
    }
    if (!await confirm(
      context,
      title: 'Demander le remboursement',
      message:
          'Vous avez payé ${c.approvedCases} case(s) '
          '(${money(c.approvedCases * c.caseAmount)}). Vous recevrez '
          '${c.approvedCases - 1} case(s), soit ${money(c.refundDue)} : la '
          'dernière case revient au tontinier (commission). Vous ne pourrez '
          'plus payer sur ce carnet.',
      confirmLabel: 'Demander',
    )) {
      return;
    }
    try {
      await Api.requestCarnetRefund(c);
      if (mounted) {
        showInfo(context, 'Demande envoyée à votre tontinier.');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Le tontinier a remis l'argent : il clôture le carnet.
  Future<void> _close(Carnet c) async {
    if (!await confirm(
      context,
      title: c.refundRequested ? 'Cotisations remboursées' : 'Carnet remis',
      message:
          'Confirmez-vous avoir remis ${money(c.refundDue)} '
          '(${c.approvedCases - 1} cases) à ${c.client?.fullName ?? 'votre client'} ? '
          'Votre commission : ${money(c.caseAmount)} (1 case). '
          'Le carnet sera clôturé.',
      confirmLabel: 'Oui, clôturer',
    )) {
      return;
    }
    try {
      await Api.closeCarnet(c);
      if (mounted) {
        showInfo(context, 'Carnet clôturé.');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _refundBanner(Carnet c, bool isOwner) => StatusCard(
    icon: Icons.undo,
    title: 'Remboursement demandé',
    message: isOwner
        ? '${c.client?.fullName ?? 'Le client'} arrête son carnet après '
              '${c.approvedCases} case(s). Remettez-lui ${money(c.refundDue)} '
              '(${c.approvedCases - 1} cases), la dernière case est votre '
              'commission, puis clôturez le carnet.'
        : 'Demande envoyée${c.refundRequestedAt == null ? '' : ' le ${dateShort(c.refundRequestedAt!)}'}. '
              'Votre tontinier doit vous remettre ${money(c.refundDue)} '
              '(${c.approvedCases - 1} cases).',
    color: paymentStatusColor(PaymentStatus.pending),
  );

  Widget _closedBanner(Carnet c, bool isOwner) => StatusCard(
    icon: Icons.task_alt,
    title: 'Carnet clôturé',
    message:
        '${isOwner ? 'Remis au client' : 'Vous avez reçu'} : '
        '${money(c.refundAmount)}'
        '${c.closedAt == null ? '' : ' le ${dateShort(c.closedAt!)}'}.',
    color: paymentStatusColor(PaymentStatus.approved),
  );

  Widget _completeBanner(Carnet c, bool isOwner) {
    final color = paymentStatusColor(PaymentStatus.approved);
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.verified, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isOwner
                    ? 'Carnet complet : remettez ${money(c.clientPayout)} à ${c.client?.fullName ?? 'votre client'}.'
                    : 'Carnet complet ! Vous recevez ${money(c.clientPayout)} de votre tontinier.',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile(Carnet c, Payment p, bool isOwner) {
    return Card(
      child: ListTile(
        leading: Icon(p.isCash ? Icons.payments_outlined : Icons.receipt_long),
        title: Text(
          '${p.caseCount} case${p.caseCount > 1 ? 's' : ''} · ${money(p.amount)}',
        ),
        subtitle: Text(
          p.status == PaymentStatus.rejected
              ? '${dateTime(p.declaredAt)}\nRefusé : ${p.rejectionReason ?? ''}'
              : '${methodLabel(p.method)}${p.recordedByOwner ? ' (encaissé)' : ''} · '
                    '${dateTime(p.declaredAt)}',
        ),
        isThreeLine: p.status == PaymentStatus.rejected,
        trailing: StatusChip.payment(p.status),
        onTap: () => _openPayment(c, p, isOwner),
      ),
    );
  }
}

class _CasesGrid extends StatelessWidget {
  const _CasesGrid({required this.carnet});

  final Carnet carnet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final approvedColor = paymentStatusColor(PaymentStatus.approved);
    final pendingColor = paymentStatusColor(PaymentStatus.pending);
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 1; i <= carnet.caseCount; i++)
          Builder(
            builder: (context) {
              final approved = i <= carnet.approvedCases;
              final pending =
                  !approved && i <= carnet.approvedCases + carnet.pendingCases;
              final isCommission = i == carnet.caseCount;
              final bg = approved
                  ? approvedColor
                  : pending
                  ? pendingColor.withValues(alpha: 0.25)
                  : scheme.surface;
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCommission
                        ? scheme.tertiary
                        : approved
                        ? approvedColor
                        : scheme.outlineVariant,
                    width: isCommission ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$i',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: approved ? Colors.white : scheme.onSurface,
                      ),
                    ),
                    if (isCommission)
                      Text(
                        'com.',
                        style: TextStyle(
                          fontSize: 9,
                          color: approved ? Colors.white : scheme.tertiary,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label, {bool outlined = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: outlined ? null : color,
            border: Border.all(color: color, width: outlined ? 2 : 1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(paymentStatusColor(PaymentStatus.approved), 'Payée'),
        item(
          paymentStatusColor(PaymentStatus.pending).withValues(alpha: 0.4),
          'En attente',
        ),
        item(
          Theme.of(context).colorScheme.tertiary,
          'Case commission',
          outlined: true,
        ),
      ],
    );
  }
}
