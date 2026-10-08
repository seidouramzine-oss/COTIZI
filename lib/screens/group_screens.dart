import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';
import '../reports.dart';
import '../widgets/common.dart';
import '../widgets/trust.dart';
import 'group_actions.dart';
import 'group_form.dart';
import 'payment_screens.dart';
import 'subscription_screens.dart';

/// Nom affiché du tontinier : son activité s'il l'a renseignée.
String ownerLabel(Group g, Business? b) => b?.name ?? g.ownerName;

/// Paiement d'un groupe ouvert par le tontinier (validation) ou par le
/// participant (consultation, reçu).
Widget groupPaymentScreen(
  Group g,
  Payment p, {
  required bool canReview,
  Business? business,
}) => ReviewPaymentScreen(
  payment: p,
  canReview: canReview,
  details: [
    ('Groupe', g.name),
    (
      'Cotisations',
      '${contributionsLabel(p.count)} × ${money(g.contributionAmount)}',
    ),
  ],
  onReview: (approve, reason) =>
      Api.reviewContributions(g.id, p, approve, reason),
  receipt: groupReceipt(g, p, business),
);

String groupReceipt(Group g, Payment p, Business? business) => receiptText(
  p,
  tontine: g.tontineName,
  item: 'Groupe : ${g.name}',
  owner: ownerLabel(g, business),
  detail: '${contributionsLabel(p.count)} × ${money(g.contributionAmount)}',
);

/// Paiement de cotisations par le participant (une ou plusieurs à la fois).
Widget payContributionsScreen(
  Group g,
  GroupMember me,
  MemberStanding s, {
  Business? business,
}) => DeclarePaymentScreen(
  title: 'Payer mes cotisations',
  unitAmount: g.contributionAmount,
  maxUnits: s.remaining,
  initialUnits: max(1, s.late),
  unitsLabel: 'Nombre de cotisations payées',
  ownerName: ownerLabel(g, business),
  accounts: business?.accounts ?? const [],
  penaltyFor: (n) => g.penaltyFor(me.declaredCount + 1, n, DateTime.now()),
  unitsCaption: (n) => n == 1
      ? 'Cotisation du ${dateShort(g.contributionDate(me.declaredCount + 1))}'
      : 'Cotisations du ${dateShort(g.contributionDate(me.declaredCount + 1))} '
            'au ${dateShort(g.contributionDate(me.declaredCount + n))}',
  note: s.late > 0
      ? 'Vous avez ${contributionsLabel(s.late)} en retard '
            '(${money(s.late * g.contributionAmount)}'
            '${s.penaltyDue > 0 ? ' + ${money(s.penaltyDue)} de pénalités' : ''}).'
      : 'Vous êtes à jour. Vous pouvez aussi payer d\'avance.',
  details: [
    ('Groupe', g.name),
    (
      'Cotisation',
      '${money(g.contributionAmount)} · ${frequencyLower(g.frequency)}',
    ),
    ('Déjà payées', '${s.declared} / ${s.total}'),
  ],
  onSubmit: (count, method, proof, mime, note, reference) =>
      Api.declareContributions(
        group: g,
        count: count,
        method: method,
        proof: proof,
        mime: mime,
        note: note,
        reference: reference,
      ),
);

/// Message de relance d'un participant en retard.
String reminderText(Group g, GroupMember m, MemberStanding s, String owner) =>
    'Bonjour ${m.name}, petit rappel pour le groupe « ${g.name} » '
    '(${g.tontineName}) : vous avez ${contributionsLabel(s.late)} en retard, '
    'soit ${money(s.late * g.contributionAmount + s.penaltyDue)}'
    '${s.penaltyDue > 0 ? ' pénalités comprises' : ''}. Merci de régulariser '
    'et de déclarer votre paiement dans COTIZI. — $owner';

/// Relance d'un participant pour la cagnotte en cours (collecte incomplète).
String shortfallText(Group g, PotShortfall f, String owner) =>
    'Bonjour ${f.member.name}, la cagnotte n°${g.currentPot} du groupe '
    '« ${g.name} » ne peut être remise que lorsque tout le monde a payé. '
    'Vous avez ${contributionsLabel(f.late)} en retard '
    '(${money(f.late * g.contributionAmount)}). '
    'Merci de payer et de déclarer votre paiement dans COTIZI. — $owner';

/// Message pour tout le groupe (à envoyer dans le groupe WhatsApp).
String shortfallGroupText(Group g, List<PotShortfall> list, String owner) => [
  'Groupe « ${g.name} » : la cagnotte n°${g.currentPot} '
      '(${money(g.netPot)}) sera remise dès que la collecte est complète. '
      'Il manque encore ${money(g.missingFor(g.currentPot))} :',
  for (final f in list)
    '• ${f.member.name} : ${contributionsLabel(f.late)} en retard '
        '(${money(f.late * g.contributionAmount)})',
  'Merci de régulariser rapidement. — $owner',
].join('\n');

/// Reçu de remise d'une cagnotte.
String payoutReceipt(Group g, Payout p, String owner) => [
  'REÇU DE REMISE — COTIZI',
  'N° ${p.receiptNumberIn(g.id)}',
  'Tontine : ${g.tontineName}',
  'Groupe : ${g.name}',
  'Cagnotte n°${p.pot} sur ${g.memberCount}',
  'Bénéficiaire : ${p.beneficiaryName}',
  'Collecte : ${money(g.grossPot)}',
  'Commission : ${money(g.commission)}',
  'Montant remis : ${money(p.amount)}',
  'Remise le ${dateTime(p.paidAt)}'
      '${p.method == null ? '' : ' (${methodLabel(p.method!).toLowerCase()})'}',
  'Tontinier : $owner',
  if (p.receivedAt != null)
    'Réception confirmée par le bénéficiaire le ${dateTime(p.receivedAt!)}'
  else
    'Réception pas encore confirmée par le bénéficiaire',
  'Enregistré dans COTIZI : ni modifiable ni supprimable.',
].join('\n');

/// Détail d'un groupe, vu par le tontinier ou par un participant.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupData {
  const _GroupData(this.group, this.payments, this.payouts, this.business);

  final Group group;
  final List<Payment> payments;
  final Map<int, Payout> payouts;

  /// Profil pro du tontinier.
  final Business? business;
}

class _GroupScreenState extends State<GroupScreen> {
  late Future<_GroupData> _data = _fetch();
  _GroupData? _last;
  bool _busy = false;

  /// Charge puis redessine aussi la barre d'actions (qui dépend des données).
  Future<_GroupData> _fetch() => _load().then((d) {
    if (mounted) setState(() {});
    return d;
  });

  Future<_GroupData> _load() async {
    final group = await Api.group(widget.groupId);
    final results = await Future.wait([
      Api.groupPayments(group),
      group.isStarted && !group.isLegacy
          ? Api.payouts(group.id)
          : Future.value(<int, Payout>{}),
      Api.business(group.ownerId),
    ]);
    return _last = _GroupData(
      group,
      results[0] as List<Payment>,
      results[1] as Map<int, Payout>,
      results[2] as Business?,
    );
  }

  void _reload() => setState(() => _data = _fetch());

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showInfo(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  /// Toutes les cagnottes sont remises : le tontinier clôture le groupe.
  Future<void> _closeGroup(_GroupData d) async {
    final g = d.group;
    final open = d.payouts.values.where(
      (p) => !p.confirmed && !(g.beneficiaryOf(p.pot)?.managed ?? true),
    );
    if (!await confirm(
      context,
      title: 'Clôturer le groupe',
      message:
          'Les ${g.memberCount} cagnottes ont été remises. '
          '${open.isEmpty ? '' : '${open.length} remise(s) ne sont pas encore confirmées par les bénéficiaires. '}'
          'Le groupe passera dans les tontines terminées et ne pourra plus '
          'être modifié.',
      confirmLabel: 'Clôturer',
    )) {
      return;
    }
    await _run(() => Api.closeGroup(g), done: 'Groupe clôturé');
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
  }

  Tontine _tontineOf(Group g) => Tontine(
    id: g.tontineId,
    ownerId: g.ownerId,
    name: g.tontineName,
    type: TontineType.cagnotte,
  );

  Future<void> _delete(Group g) async {
    if (!await confirm(
      context,
      title: 'Supprimer le groupe',
      message:
          'Le groupe « ${g.name} » et ses ${g.joinedCount} inscription(s) '
          'seront supprimés. Son lien d\'invitation ne marchera plus.',
      confirmLabel: 'Supprimer',
    )) {
      return;
    }
    try {
      await Api.deleteGroup(g);
      if (!mounted) return;
      showInfo(context, 'Groupe supprimé');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addManaged(Group g) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const AddManagedMemberDialog(),
    );
    if (result == null) return;
    await _run(
      () => Api.addManagedMember(g, result.$1, result.$2),
      done: '${result.$1} ajouté au groupe',
    );
  }

  Future<void> _remove(Group g, GroupMember m) async {
    if (await confirm(
      context,
      title: 'Retirer ${m.name}',
      message: 'Sa place sera libérée pour quelqu\'un d\'autre.',
      confirmLabel: 'Retirer',
    )) {
      await _run(() => Api.removeMember(g, m), done: '${m.name} retiré');
    }
  }

  Future<void> _drawLot(Group g) => _run(() async {
    final position = await Api.drawLot(g.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.celebration, size: 40),
        title: Text('Vous avez tiré le n°$position'),
        content: Text(
          'Vous recevrez la cagnotte n°$position de ${money(g.netPot)} '
          '(prévue le ${dateLong(g.payoutDate(position))} si la tontine '
          'démarre à la date prévue).',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  });

  Future<void> _confirmPayout(Group g) async {
    final pot = g.currentPot;
    final b = g.beneficiaryOf(pot);
    if (b == null || !g.isPotComplete(pot)) return;
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PayoutSheet(group: g, beneficiary: b),
    );
    if (method == null) return;
    await _run(
      () => Api.confirmPayout(g, method),
      done: 'Remise de la cagnotte n°$pot enregistrée',
    );
  }

  Future<void> _answerPayout(Group g, Payout p, {required bool ok}) async {
    if (ok) {
      if (await confirm(
        context,
        title: 'Cagnotte reçue',
        message: 'Confirmez-vous avoir reçu ${money(p.amount)} ?',
        confirmLabel: 'Oui, j\'ai reçu',
      )) {
        await _run(
          () => Api.answerPayout(g.id, p),
          done: 'Réception confirmée',
        );
      }
      return;
    }
    final problem = await showDialog<String>(
      context: context,
      builder: (_) => const _ProblemDialog(),
    );
    if (problem != null) {
      await _run(
        () => Api.answerPayout(g.id, p, problem: problem),
        done: 'Problème signalé au tontinier',
      );
    }
  }

  void _record(Group g, GroupMember m, Business? b) {
    final s = g.standingOf(m, DateTime.now());
    _push(
      RecordPaymentScreen(
        payerName: m.name,
        details: [
          ('Participant', m.name),
          ('Groupe', g.name),
          ('Déjà payées', '${s.declared} / ${s.total}'),
          if (s.late > 0) ('En retard', contributionsLabel(s.late)),
        ],
        unitAmount: g.contributionAmount,
        maxUnits: s.remaining,
        initialUnits: max(1, s.late),
        unitsLabel: 'Nombre de cotisations',
        penaltyFor: (n) => g.penaltyFor(m.declaredCount + 1, n, DateTime.now()),
        onSubmit: (count, method, penalty, note, reference) async {
          final p = await Api.recordPayment(
            group: g,
            member: m,
            count: count,
            method: method,
            penalty: penalty,
            note: note,
            reference: reference,
          );
          return groupReceipt(g, p, b);
        },
      ),
    );
  }

  Future<void> _statement(_GroupData d, GroupMember m) => _run(
    () => shareMemberStatement(
      group: d.group,
      member: m,
      payments: d.payments,
      payouts: d.payouts,
      business: d.business,
    ),
  );

  /// Fiche d'un participant (tontinier) : encaisser, relancer, relevé.
  Future<void> _memberSheet(_GroupData d, GroupMember m) async {
    final g = d.group;
    final s = g.standingOf(m, DateTime.now());
    final owner = ownerLabel(g, d.business);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                m.name,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${m.profile.phone}${m.managed ? ' · sans application' : ''}\n'
                '${s.approved} / ${s.total} validées'
                '${s.late > 0 ? ' · ${s.late} en retard' : ' · à jour'}'
                '${m.penaltyPaid > 0 ? ' · pénalités ${money(m.penaltyPaid)}' : ''}',
              ),
              isThreeLine: true,
            ),
            const Divider(),
            if (g.status == GroupStatus.active && s.remaining > 0)
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: const Text('Encaisser un paiement'),
                subtitle: const Text('Espèces ou Mobile Money reçus'),
                onTap: () => Navigator.pop(context, 'record'),
              ),
            if (s.late > 0)
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Relancer sur WhatsApp'),
                onTap: () => Navigator.pop(context, 'remind'),
              ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Relevé PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            if (m.managed)
              ListTile(
                leading: const Icon(Icons.install_mobile),
                title: const Text('Inviter à utiliser COTIZI'),
                subtitle: const Text('Il retrouvera sa place avec ce lien'),
                onTap: () => Navigator.pop(context, 'invite'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'record':
        _record(g, m, d.business);
      case 'remind':
        await openWhatsApp(
          context,
          m.profile.phone,
          reminderText(g, m, s, owner),
        );
      case 'pdf':
        await _statement(d, m);
      case 'invite':
        await openWhatsApp(
          context,
          m.profile.phone,
          inviteMessage(
            'Bonjour ${m.name}, suivez vos cotisations du groupe « ${g.name} » '
            'sur COTIZI. Inscrivez-vous comme « Client » avec ce numéro '
            '(${m.profile.phone}) : vous retrouverez votre place.',
            g.inviteCode,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _last;
    final g = d?.group;
    final isOwner = g?.ownerId == Api.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groupe'),
        actions: [
          if (g != null && !g.isLegacy) ...[
            IconButton(
              tooltip: 'Règlement',
              icon: const Icon(Icons.gavel_outlined),
              onPressed: () => _push(RulesScreen(group: g)),
            ),
            IconButton(
              tooltip: 'Historique',
              icon: const Icon(Icons.history),
              onPressed: () => _push(GroupEventsScreen(group: g)),
            ),
            if (isOwner)
              PopupMenuButton<String>(
                tooltip: 'Plus d\'actions',
                onSelected: (v) => switch (v) {
                  'edit' => _push(
                    GroupFormScreen(tontine: _tontineOf(g), group: g),
                  ),
                  'pdf' => _run(
                    () => shareGroupReport(
                      group: g,
                      payments: d!.payments,
                      payouts: d.payouts,
                      business: d.business,
                    ),
                  ),
                  'delete' => _delete(g),
                  _ => null,
                },
                itemBuilder: (context) => [
                  if (g.status == GroupStatus.recruiting)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifier le groupe'),
                    ),
                  const PopupMenuItem(
                    value: 'pdf',
                    child: Text('Bilan PDF du groupe'),
                  ),
                  if (!g.isStarted)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer le groupe'),
                    ),
                ],
              )
            else ...[
              if ((d?.business?.contactPhone ?? '').isNotEmpty)
                IconButton(
                  tooltip: 'Écrire au tontinier',
                  icon: const Icon(Icons.chat_outlined),
                  onPressed: () => openWhatsApp(
                    context,
                    d!.business!.contactPhone,
                    'Bonjour, j\'ai une question sur le groupe « ${g.name} ».',
                  ),
                ),
            ],
            if (!isOwner && g.memberById(Api.uid) != null)
              IconButton(
                tooltip: 'Mon relevé PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _statement(d!, g.memberById(Api.uid)!),
              ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureView<_GroupData>(
          future: _data,
          onRetry: _reload,
          builder: (context, d) {
            final g = d.group;
            final isOwner = g.ownerId == Api.uid;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(g, d.business, isOwner),
                if (!g.isLegacy && !g.isClosed)
                  PausedBanner(
                    ownerId: g.ownerId,
                    ownerName: g.ownerName,
                    isOwner: isOwner,
                    onRenew: () => _push(const SubscriptionScreen()),
                  ),
                if (g.isLegacy) ...[
                  _legacyNotice(),
                  ..._membersSection(g, isOwner: false),
                ] else
                  ...switch (g.status) {
                    GroupStatus.recruiting => _recruiting(g, isOwner),
                    GroupStatus.drawing => _drawing(g, isOwner),
                    GroupStatus.ready => _ready(g, isOwner),
                    GroupStatus.active ||
                    GroupStatus.finished => _started(d, isOwner),
                  },
                if (!isOwner && !g.isLegacy) ...[
                  const SectionTitle('Votre tontinier'),
                  TrustCard(ownerId: g.ownerId, ownerName: g.ownerName),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(Group g, Business? b, bool isOwner) {
    final theme = Theme.of(context);
    final logo = b?.logo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b != null && !isOwner) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: logo == null
                        ? null
                        : MemoryImage(base64.decode(logo)),
                    child: logo == null
                        ? const Icon(Icons.storefront, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusChip(
                  groupStatusLabel(g.status),
                  g.status == GroupStatus.finished
                      ? paymentStatusColor(PaymentStatus.approved)
                      : theme.colorScheme.primary,
                ),
              ],
            ),
            Text(
              '${g.tontineName} · Tontinier : ${g.ownerName}',
              style: theme.textTheme.bodySmall,
            ),
            if (!g.isLegacy) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.date_range,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.isStarted
                          ? 'Du ${dateLong(g.startDate)} au ${dateLong(g.endDate)}'
                          : 'Début prévu le ${dateShort(g.startDate)} · fin '
                                'prévue le ${dateShort(g.endDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            FigureGrid([
              Figure(
                'Cotisation',
                money(g.contributionAmount),
                caption: frequencyLower(g.frequency),
              ),
              if (g.isLegacy)
                Figure('Premier tour', dateShort(g.startDate))
              else
                Figure(
                  'Collecte',
                  durationLabel(g.frequency, g.perPot),
                  caption: 'avant chaque remise',
                ),
              Figure(
                'Cagnotte',
                money(g.grossPot),
                caption: 'reçu : ${money(g.netPot)}',
              ),
              Figure(
                'Participants',
                '${g.joinedCount} / ${g.memberCount}',
                caption: g.hasPenalty
                    ? 'pénalité ${penaltyShort(g)}'
                    : 'commission ${commissionLabel(g)}',
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _legacyNotice() => const Padding(
    padding: EdgeInsets.only(top: 4),
    child: _Notice(
      icon: Icons.history,
      text:
          'Ce groupe a été créé avec une ancienne version de COTIZI. Il reste '
          'consultable, mais les paiements se font dans les nouveaux groupes.',
    ),
  );

  /// Règlement à accepter (participant) ou suivi des acceptations
  /// (tontinier), avant le démarrage.
  List<Widget> _acceptance(Group g, bool isOwner) {
    if (!g.needsAcceptance || g.isStarted) return const [];
    final wait = paymentStatusColor(PaymentStatus.pending);
    final good = paymentStatusColor(PaymentStatus.approved);
    if (!isOwner) {
      if (!g.memberIds.contains(Api.uid)) return const [];
      return [
        g.hasAccepted(Api.uid)
            ? StatusCard(
                icon: Icons.verified_outlined,
                title: 'Règlement accepté',
                message: 'Vous avez accepté les conditions du tontinier.',
                color: good,
                onTap: () => _push(RulesScreen(group: g)),
              )
            : StatusCard(
                icon: Icons.gavel_outlined,
                title: 'Règlement à accepter',
                message:
                    'Lisez les conditions fixées par le tontinier (cotisations, '
                    'pénalités, règles) et acceptez-les : la tontine ne peut '
                    'pas démarrer sans votre accord.',
                color: wait,
                children: [
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _push(RulesScreen(group: g)),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: const Text('Lire et accepter le règlement'),
                  ),
                ],
              ),
      ];
    }
    final total = g.memberIds.length;
    final pending = g.pendingAcceptance;
    return [
      StatusCard(
        icon: pending.isEmpty ? Icons.verified_outlined : Icons.gavel_outlined,
        title:
            'Règlement accepté par ${total - g.pendingAcceptanceCount} / '
            '$total',
        message: pending.isEmpty
            ? 'Tous les participants avec l\'application ont accepté le '
                  'règlement.'
            : 'En attente : ${pending.map((m) => m.name).join(', ')}. La '
                  'tontine ne pourra démarrer qu\'après leur accord.',
        color: pending.isEmpty ? good : wait,
        onTap: () => _push(RulesScreen(group: g)),
        children: [
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final m in pending)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openWhatsApp(
                    context,
                    m.profile.phone,
                    'Bonjour ${m.name}, merci d\'ouvrir COTIZI et d\'accepter le '
                    'règlement du groupe « ${g.name} » pour que la tontine '
                    'puisse démarrer.',
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: Text('Rappeler ${m.name}'),
                ),
              ),
          ],
        ],
      ),
    ];
  }

  // ------------------------------------------------------- Inscriptions

  List<Widget> _recruiting(Group g, bool isOwner) {
    final full = g.joinedCount >= g.memberCount;
    if (!isOwner) {
      return [
        ..._acceptance(g, false),
        _Notice(
          icon: Icons.hourglass_top,
          text: full
              ? 'Le groupe est complet. Le tontinier va fixer l\'ordre des '
                    'remises puis démarrer la tontine.'
              : 'En attente des autres participants (${g.joinedCount} / '
                    '${g.memberCount}).',
        ),
        ..._membersSection(g, isOwner: false),
      ];
    }
    return [
      const SizedBox(height: 4),
      ..._acceptance(g, true),
      InviteCodeCard(
        code: g.inviteCode,
        hint:
            'Appuyez sur Partager : vos participants recevront un lien pour '
            'rejoindre le groupe.',
        shareText: inviteMessage(
          'Rejoins le groupe « ${g.name} » de ma tontine sur COTIZI. '
          'Cotisation : ${money(g.contributionAmount)} '
          '${frequencyLower(g.frequency)}, cagnotte de ${money(g.netPot)} '
          'remise tous les ${durationLabel(g.frequency, g.perPot)}.',
          g.inviteCode,
        ),
      ),
      const SizedBox(height: 8),
      if (!full)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _addManaged(g),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Ajouter un participant sans application'),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: !full || _busy
            ? null
            : g.orderMode == OrderMode.manual
            ? () => _push(OrderScreen(group: g))
            : () async {
                if (await confirm(
                  context,
                  title: 'Lancer le tirage au sort',
                  message:
                      'Plus personne ne pourra rejoindre le groupe. Chaque '
                      'participant tirera son numéro : c\'est l\'ordre des '
                      'remises.',
                  confirmLabel: 'Lancer',
                )) {
                  await _run(() => Api.startDraw(g));
                }
              },
        icon: Icon(
          g.orderMode == OrderMode.manual
              ? Icons.format_list_numbered
              : Icons.casino_outlined,
        ),
        label: Text(
          !full
              ? 'Groupe incomplet (${g.joinedCount} / ${g.memberCount})'
              : g.orderMode == OrderMode.manual
              ? 'Fixer l\'ordre des remises'
              : 'Lancer le tirage au sort',
        ),
      ),
      ..._membersSection(g, isOwner: true),
    ];
  }

  // ------------------------------------------------------ Tirage au sort

  List<Widget> _drawing(Group g, bool isOwner) {
    final drawn = g.members.where((m) => m.drawPosition != null).length;
    final me = g.memberById(Api.uid);
    if (isOwner) {
      return [
        ..._acceptance(g, true),
        _Notice(
          icon: Icons.casino_outlined,
          text:
              'Tirage au sort en cours : $drawn / ${g.memberCount} numéros '
              'tirés.',
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (await confirm(
                    context,
                    title: 'Terminer le tirage',
                    message:
                        'Les participants qui n\'ont pas encore tiré (et ceux '
                        'sans application) reçoivent un numéro au hasard.',
                    confirmLabel: 'Tirer pour eux',
                  )) {
                    await _run(() => Api.finishDraw(g));
                  }
                },
          icon: const Icon(Icons.shuffle),
          label: const Text('Tirer pour les participants restants'),
        ),
        ..._membersSection(g, isOwner: false),
      ];
    }
    if (me != null && me.drawPosition == null) {
      return [
        const SizedBox(height: 4),
        ..._acceptance(g, false),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.casino, size: 48),
                const SizedBox(height: 8),
                const Text(
                  'Le tirage au sort est ouvert ! Tirez votre numéro pour '
                  'savoir quand vous recevrez la cagnotte.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _drawLot(g),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Tirer mon numéro'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      ..._acceptance(g, false),
      _Notice(
        icon: Icons.casino_outlined,
        text:
            'Vous avez tiré le n°${me?.drawPosition}. En attente des autres '
            'participants ($drawn / ${g.memberCount}).',
      ),
    ];
  }

  // ------------------------------------------------- Prête à démarrer

  List<Widget> _ready(Group g, bool isOwner) {
    final me = g.memberById(Api.uid);
    return [
      ..._acceptance(g, isOwner),
      if (isOwner) ...[
        StatusCard(
          icon: Icons.flag_outlined,
          title: 'Prête à démarrer',
          message: g.allAccepted
              ? 'L\'ordre des remises est fixé. Démarrez la tontine pour figer '
                    'les dates et ouvrir les paiements.'
              : 'L\'ordre des remises est fixé. La tontine pourra démarrer '
                    'quand tous les participants auront accepté le règlement.',
          color: Theme.of(context).colorScheme.primary,
          children: [
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || !g.allAccepted
                  ? null
                  : () => _push(StartGroupScreen(group: g)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer la tontine'),
            ),
            if (g.orderMode == OrderMode.manual) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _push(OrderScreen(group: g)),
                icon: const Icon(Icons.format_list_numbered),
                label: const Text('Modifier l\'ordre'),
              ),
            ],
          ],
        ),
      ] else
        _Notice(
          icon: Icons.flag_outlined,
          text:
              'L\'ordre des remises est fixé${me?.drawPosition == null ? '' : ' : vous recevez la cagnotte n°${me!.drawPosition}'}. '
              'Le tontinier va démarrer la tontine.',
        ),
      const SectionTitle('Ordre des remises (prévisionnel)'),
      Card(
        child: Column(
          children: [
            for (var pot = 1; pot <= g.memberCount; pot++)
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(
                    '$pot',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(_nameOf(g.beneficiaryOf(pot))),
                trailing: Text(dateShort(g.payoutDate(pot))),
              ),
          ],
        ),
      ),
    ];
  }

  String _nameOf(GroupMember? m) => m == null
      ? '—'
      : m.userId == Api.uid
      ? '${m.name} (vous)'
      : m.name;

  // ------------------------------------------- En cours ou terminée

  List<Widget> _started(_GroupData d, bool isOwner) {
    final g = d.group;
    final me = g.memberById(Api.uid);
    final myIds = me?.paymentIds ?? const <String>[];
    final toConfirm = [
      for (final p in d.payouts.values)
        if (myIds.contains(p.beneficiaryId) &&
            !p.confirmed &&
            p.problem == null)
          p,
    ];
    final last = d.payouts[g.paidOutCount];
    return [
      for (final p in toConfirm) _receptionCard(d, p),
      // Suivi de la dernière remise tant que le bénéficiaire (avec l'appli)
      // n'a pas confirmé l'avoir reçue
      if (isOwner &&
          last != null &&
          !last.confirmed &&
          !(g.beneficiaryOf(last.pot)?.managed ?? true))
        _payoutFollowUp(d, last),
      if (g.status == GroupStatus.active) _currentPot(g, isOwner),
      if (g.status == GroupStatus.finished)
        StatusCard(
          icon: Icons.verified_outlined,
          title: g.isClosed ? 'Groupe clôturé' : 'Tontine terminée',
          message:
              'Les ${g.memberCount} cagnottes ont été remises '
              '(${periodLabel(g.startDate, g.endDate)}).'
              '${g.isClosed ? ' Clôturé le ${dateShort(g.closedAt!)}.' : ''}',
          color: paymentStatusColor(PaymentStatus.approved),
        ),
      if (isOwner && g.canClose) ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => _closeGroup(d),
          icon: const Icon(Icons.task_alt),
          label: const Text('Clôturer le groupe'),
        ),
        const SizedBox(height: 8),
      ],
      if (isOwner && g.status == GroupStatus.active) ..._shortfallSection(d),
      if (!isOwner && me != null) ..._mySituation(d, me),
      if (isOwner) ..._pendingSection(d),
      if (isOwner) ..._trackingSection(d),
      ..._calendarSection(g, d.payouts),
    ];
  }

  /// Le bénéficiaire confirme avoir reçu sa cagnotte.
  Widget _receptionCard(_GroupData d, Payout p) {
    final g = d.group;
    final theme = Theme.of(context);
    return StatusCard(
      icon: Icons.savings,
      title: 'Avez-vous reçu votre cagnotte ?',
      message:
          '${ownerLabel(g, d.business)} indique vous avoir remis '
          '${money(p.amount)} le ${dateTime(p.paidAt)}'
          '${p.method == null ? '' : ', ${p.method == PaymentMethod.cash ? 'en espèces' : 'par Mobile Money'}'}'
          ' (cagnotte n°${p.pot}).',
      color: paymentStatusColor(PaymentStatus.pending),
      children: [
        const SizedBox(height: 12),
        InfoRow('Collecte', money(g.grossPot)),
        InfoRow('Commission', '− ${money(g.commission)}'),
        InfoRow('Vous recevez', money(p.amount), bold: true),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _answerPayout(g, p, ok: true),
          child: const Text('Oui, j\'ai reçu l\'argent'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _answerPayout(g, p, ok: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('Non, signaler un problème'),
        ),
      ],
    );
  }

  /// Suivi de la dernière remise : collecte complète, remise faite,
  /// réception confirmée par le bénéficiaire.
  Widget _payoutFollowUp(_GroupData d, Payout p) {
    final g = d.group;
    final theme = Theme.of(context);
    final b = g.beneficiaryOf(p.pot);
    final managed = b?.managed ?? false;
    final owner = ownerLabel(g, d.business);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cagnotte n°${p.pot} · ${p.beneficiaryName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  money(p.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const StepLine(
              title: 'Collecte complète',
              subtitle: 'Toutes les cotisations validées',
              state: StepState.complete,
            ),
            StepLine(
              title: 'Remise faite par vous',
              subtitle:
                  '${p.method == null ? '' : '${methodLabel(p.method!)} · '}'
                  '${dateTime(p.paidAt)}',
              state: StepState.complete,
            ),
            if (!managed)
              StepLine(
                title: p.problem != null
                    ? 'Problème signalé par ${p.beneficiaryName}'
                    : 'Réception confirmée par ${p.beneficiaryName}',
                subtitle: p.problem ?? 'En attente de sa réponse',
                state: p.problem != null ? StepState.error : StepState.indexed,
                last: true,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: payoutReceipt(g, p, owner)),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Reçu'),
                  ),
                ),
                if (!managed && b != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openWhatsApp(
                        context,
                        b.profile.phone,
                        'Bonjour ${b.name}, je vous ai remis ${money(p.amount)} '
                        '(cagnotte n°${p.pot}, groupe « ${g.name} »). Merci de '
                        'confirmer la réception dans COTIZI. — $owner',
                      ),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text('Rappeler ${b.name.split(' ').first}'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentPot(Group g, bool isOwner) {
    final theme = Theme.of(context);
    final pot = g.currentPot;
    final b = g.beneficiaryOf(pot);
    final isMine = b?.userId == Api.uid;
    final validated = g.collectedFor(pot);
    final declared = g.collectedFor(pot, withPending: true);
    final complete = g.isPotComplete(pot);
    final missing = g.missingFor(pot);
    final percent = g.grossPot == 0
        ? 0
        : (100 * validated / g.grossPot).floor();
    final date = g.payoutDate(pot);
    final reached = !date.isAfter(DateUtils.dateOnly(DateTime.now()));
    final good = paymentStatusColor(PaymentStatus.approved);
    final wait = paymentStatusColor(PaymentStatus.pending);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return Card(
      color: isMine ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cagnotte n°$pot sur ${g.memberCount}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusChip(
                  complete ? 'Collecte complète' : 'Collecte en cours',
                  complete ? good : wait,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FigureGrid([
              Figure(
                'Bénéficiaire',
                isMine ? 'Vous !' : (b?.name ?? '—'),
                caption: 'reçoit ${money(g.netPot)}',
              ),
              Figure(
                'Remise prévue',
                dateShort(date),
                caption: countdownLabel(date),
              ),
            ]),
            const SizedBox(height: 16),
            ProgressLine(
              value: g.grossPot == 0 ? 0 : validated / g.grossPot,
              color: complete ? good : null,
              label:
                  '${money(validated)} validés sur ${money(g.grossPot)} '
                  '($percent %)'
                  '${declared > validated ? ' · + ${money(declared - validated)} en attente' : ''}',
            ),
            const SizedBox(height: 4),
            Text(
              'Collecte ${periodLabel(g.collectStart(pot), g.collectEnd(pot))}',
              style: theme.textTheme.bodySmall,
            ),
            if (isOwner && b != null) ...[
              const SizedBox(height: 12),
              if (complete)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _confirmPayout(g),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Remettre la cagnotte à ${b.name}'),
                )
              else ...[
                reached
                    ? LockNotice(
                        color: bad,
                        title: 'Remise impossible pour l\'instant',
                        text:
                            'La date de remise est atteinte mais il manque '
                            '${money(missing)}. La remise se débloque dès que '
                            'toute la collecte est validée.',
                      )
                    : LockNotice(
                        color: theme.colorScheme.onSurfaceVariant,
                        title: 'Collecte en cours',
                        text:
                            'La remise sera possible quand toutes les '
                            'cotisations de cette cagnotte seront payées '
                            '(encore ${money(missing)} à collecter).',
                      ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Remettre la cagnotte'),
                ),
              ],
            ] else if (!complete) ...[
              const SizedBox(height: 10),
              Text(
                isMine
                    ? 'Elle vous sera remise dès que toute la collecte est '
                          'payée : il manque encore ${money(missing)}.'
                    : 'La cagnotte est remise dès que toute la collecte est '
                          'payée (il manque ${money(missing)}).',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Participants en retard pour la cagnotte en cours (cotisations déjà
  /// dues, aujourd'hui compris, mais pas déclarées), avec relance.
  List<Widget> _shortfallSection(_GroupData d) {
    final g = d.group;
    final pot = g.currentPot;
    if (g.isPotComplete(pot)) return const [];
    final list = g.lateFor(pot);
    if (list.isEmpty) return const [];
    final owner = ownerLabel(g, d.business);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    final reachable = list.where((f) => !f.member.managed).toList();
    return [
      SectionTitle(
        'En retard pour cette cagnotte',
        trailing: Text(
          '${list.length} participant${list.length > 1 ? 's' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final f in list)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: bad.withValues(alpha: 0.12),
                  foregroundColor: bad,
                  child: Text(
                    initials(f.member.name),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(f.member.name),
                subtitle: Text(
                  '${contributionsLabel(f.late)} en retard · '
                  '${money(f.late * g.contributionAmount)}'
                  '${f.member.managed ? ' · sans appli' : ''}',
                  style: TextStyle(color: bad, fontWeight: FontWeight.w600),
                ),
                trailing: f.member.managed
                    ? OutlinedButton(
                        onPressed: () => _record(g, f.member, d.business),
                        child: const Text('Encaisser'),
                      )
                    : OutlinedButton(
                        onPressed: () => openWhatsApp(
                          context,
                          f.member.profile.phone,
                          shortfallText(g, f, owner),
                        ),
                        child: const Text('Relancer'),
                      ),
                onTap: () => _memberSheet(d, f.member),
              ),
          ],
        ),
      ),
      if (reachable.length > 1)
        FilledButton.icon(
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: shortfallGroupText(g, list, owner)),
          ),
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Relancer tout le monde (groupe WhatsApp)'),
        ),
    ];
  }

  List<Widget> _mySituation(_GroupData d, GroupMember me) {
    final g = d.group;
    final s = g.standingOf(me, DateTime.now());
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    final mine = d.payments
        .where((p) => me.paymentIds.contains(p.userId))
        .toList();
    final pos = me.drawPosition;
    final payout = pos == null ? null : d.payouts[pos];
    return [
      const SectionTitle('Ma situation'),
      StatusCard(
        icon: s.allPaid
            ? Icons.verified
            : s.upToDate
            ? Icons.check_circle
            : Icons.warning_amber_rounded,
        color: s.upToDate ? good : bad,
        title: s.allPaid
            ? 'Toutes vos cotisations sont payées'
            : s.upToDate
            ? 'Vous êtes à jour'
            : '${contributionsLabel(s.late)} en retard',
        message: s.upToDate
            ? [
                if (s.pending > 0)
                  '${contributionsLabel(s.pending)} en attente de validation.',
                if (s.ahead > 0)
                  'Vous avez payé ${contributionsLabel(s.ahead)} d\'avance.',
                if (s.remaining > 0)
                  'Prochaine cotisation : '
                      '${dateLong(g.contributionDate(s.declared + 1))}.',
              ].join(' ')
            : 'À régulariser : ${money(s.late * g.contributionAmount)}'
                  '${s.penaltyDue > 0 ? ' + ${money(s.penaltyDue)} de pénalités' : ''}.',
        children: [
          const SizedBox(height: 12),
          ProgressLine(
            value: s.total == 0 ? 0 : s.approved / s.total,
            color: good,
            label:
                '${s.approved} / ${s.total} cotisations validées'
                '${s.pending > 0 ? ' · ${s.pending} en attente' : ''}'
                '${me.penaltyPaid > 0 ? ' · pénalités payées ${money(me.penaltyPaid)}' : ''}',
          ),
          if (s.remaining > 0 && g.status == GroupStatus.active) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  _push(payContributionsScreen(g, me, s, business: d.business)),
              icon: const Icon(Icons.upload),
              label: Text(
                s.late > 0 ? 'Payer mes cotisations en retard' : 'Payer',
              ),
            ),
          ],
        ],
      ),
      if (pos != null)
        Card(
          child: ListTile(
            leading: Icon(
              payout?.confirmed == true
                  ? Icons.done_all
                  : Icons.emoji_events_outlined,
              color: payout?.confirmed == true ? good : null,
            ),
            title: Text(
              payout != null
                  ? 'Cagnotte n°$pos reçue'
                  : 'Vous recevez la cagnotte n°$pos',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              payout != null
                  ? '${money(payout.amount)} le ${dateLong(payout.paidAt)}'
                        '${payout.confirmed ? ' · réception confirmée' : ''}'
                  : '${money(g.netPot)} · le ${dateLong(g.payoutDate(pos))}',
            ),
          ),
        ),
      if (mine.isNotEmpty) ...[
        SectionTitle('Mes paiements (${mine.length})'),
        for (final p in mine)
          Card(
            child: ListTile(
              leading: Icon(
                p.isCash ? Icons.payments_outlined : Icons.phone_android,
              ),
              title: Text(
                '${contributionsLabel(p.count)} · ${money(p.amount)}',
              ),
              subtitle: Text(
                p.status == PaymentStatus.rejected
                    ? 'Refusé : ${p.rejectionReason ?? ''}'
                    : '${methodLabel(p.method)} · ${dateTime(p.declaredAt)}',
              ),
              trailing: StatusChip.payment(p.status),
              onTap: () => _push(
                groupPaymentScreen(
                  g,
                  p,
                  canReview: false,
                  business: d.business,
                ),
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _pendingSection(_GroupData d) {
    final pending = d.payments
        .where((p) => p.status == PaymentStatus.pending)
        .toList();
    if (pending.isEmpty) return const [];
    final color = paymentStatusColor(PaymentStatus.pending);
    return [
      SectionTitle('Paiements à valider (${pending.length})'),
      for (final p in pending)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: Icon(
                p.isCash ? Icons.payments_outlined : Icons.receipt_long,
              ),
            ),
            title: Text(p.payer.fullName),
            subtitle: Text(
              '${contributionsLabel(p.count)} · ${methodLabel(p.method)} · '
              '${dateTime(p.declaredAt)}',
            ),
            trailing: Text(
              money(p.amount),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: () => _push(
              groupPaymentScreen(
                d.group,
                p,
                canReview: true,
                business: d.business,
              ),
            ),
          ),
        ),
    ];
  }

  /// Suivi des participants : à jour ou en retard ; fiche avec encaissement,
  /// relance et relevé.
  List<Widget> _trackingSection(_GroupData d) {
    final g = d.group;
    final today = DateTime.now();
    final standings = [for (final m in g.members) (m, g.standingOf(m, today))];
    final lateCount = standings.where((e) => !e.$2.upToDate).length;
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return [
      SectionTitle(
        'Suivi des participants',
        trailing: Text(
          lateCount == 0 ? 'Tous à jour' : '$lateCount en retard',
          style: TextStyle(
            color: lateCount == 0 ? good : bad,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      for (final (m, s) in standings)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                m.drawPosition == null ? '?' : '${m.drawPosition}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(m.managed ? '${m.name} (sans appli)' : m.name),
            subtitle: Text(
              s.upToDate
                  ? '${s.approved} / ${s.total} validées'
                        '${s.pending > 0 ? ' · ${s.pending} en attente' : ''}'
                  : '${contributionsLabel(s.late)} en retard · '
                        '${money(s.late * g.contributionAmount + s.penaltyDue)}',
              style: TextStyle(color: s.upToDate ? null : bad),
            ),
            trailing: s.upToDate
                ? StatusChip('À jour', good)
                : StatusChip('Retard', bad),
            onTap: () => _memberSheet(d, m),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Touchez un participant pour encaisser, relancer ou voir son relevé.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  List<Widget> _calendarSection(Group g, Map<int, Payout> payouts) {
    final theme = Theme.of(context);
    final good = paymentStatusColor(PaymentStatus.approved);
    return [
      const SectionTitle('Calendrier des remises'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var pot = 1; pot <= g.memberCount; pot++)
              Builder(
                builder: (context) {
                  final b = g.beneficiaryOf(pot);
                  final done = payouts[pot];
                  final current =
                      g.status == GroupStatus.active && pot == g.currentPot;
                  final mine = b?.userId == Api.uid;
                  return ListTile(
                    tileColor: mine
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.5,
                          )
                        : null,
                    leading: CircleAvatar(
                      backgroundColor: done != null
                          ? good.withValues(alpha: 0.15)
                          : null,
                      foregroundColor: done != null ? good : null,
                      child: done != null
                          ? Icon(done.confirmed ? Icons.done_all : Icons.check)
                          : Text(
                              '$pot',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    title: Text(
                      _nameOf(b),
                      style: TextStyle(
                        fontWeight: current || mine
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      done != null
                          ? 'Remise le ${dateShort(done.paidAt)} · '
                                '${money(done.amount)}'
                                '${done.confirmed
                                    ? ' · reçue ✔✔'
                                    : done.problem != null
                                    ? ' · problème signalé'
                                    : ''}'
                          : 'Remise prévue le ${dateShort(g.payoutDate(pot))}',
                    ),
                    trailing: done != null
                        ? StatusChip(
                            done.problem != null ? 'Problème' : 'Remise',
                            done.problem != null
                                ? paymentStatusColor(PaymentStatus.rejected)
                                : good,
                          )
                        : current
                        ? StatusChip(
                            'En cours',
                            paymentStatusColor(PaymentStatus.pending),
                          )
                        : const StatusChip('À venir', Colors.grey),
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _membersSection(Group g, {required bool isOwner}) {
    return [
      SectionTitle('Participants (${g.members.length} / ${g.memberCount})'),
      if (g.members.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Aucun participant pour le moment.'),
        ),
      for (final m in g.members)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase()),
            ),
            title: Text(_nameOf(m)),
            subtitle: Text(
              m.managed
                  ? '${m.profile.phone} · sans application'
                  : g.needsAcceptance && !g.isStarted
                  ? '${m.profile.phone} · ${g.hasAccepted(m.userId) ? 'règlement accepté' : 'règlement à accepter'}'
                  : m.profile.phone,
            ),
            trailing: isOwner && g.status == GroupStatus.recruiting
                ? IconButton(
                    tooltip: 'Retirer ${m.name}',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: _busy ? null : () => _remove(g, m),
                  )
                : m.drawPosition == null
                ? null
                : StatusChip(
                    'N° ${m.drawPosition}',
                    Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
    ];
  }
}

class _ProblemDialog extends StatefulWidget {
  const _ProblemDialog();

  @override
  State<_ProblemDialog> createState() => _ProblemDialogState();
}

class _ProblemDialogState extends State<_ProblemDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signaler un problème'),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLines: 3,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Que s\'est-il passé ?',
          hintText: 'Ex. Je n\'ai reçu que 100 000 F',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
