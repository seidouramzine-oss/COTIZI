import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../pro.dart';
import '../reports.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'subscription_screens.dart';

String _monthLabel(DateTime m) {
  final s = DateFormat('MMMM yyyy', 'fr').format(m);
  return s[0].toUpperCase() + s.substring(1);
}

String _signed(int v) => '${v < 0 ? '− ' : ''}${money(v.abs())}';

/// Ouvre une fonction du plan Pro, ou propose de passer à Pro.
Future<void> openPro(BuildContext context, Widget screen) async {
  final results = await Future.wait([
    Api.reloadProfile(),
    Api.isAdmin(),
    Api.coveredByCompany(),
  ]);
  if (!context.mounted) return;
  final profile = results[0] as Profile?;
  final admin = results[1] as bool;
  final agent = results[2] as bool;
  final allowed = admin
      ? adminPlanView.value != 'free'
      : agent || (profile?.isProAt(DateTime.now()) ?? false);
  if (allowed) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: const Text('Réservé au plan Pro'),
      content: const Text(
        'La comptabilité, les statistiques avancées et le badge vérifié font '
        'partie du plan Pro. Passez à Pro pour les utiliser.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Passer à Pro'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
  }
}

/// Petit badge « Vérifié » affiché à côté du nom d'un tontinier.
class VerifiedBadge extends StatefulWidget {
  const VerifiedBadge({super.key, required this.ownerId, this.large = false});

  final String ownerId;
  final bool large;

  @override
  State<VerifiedBadge> createState() => _VerifiedBadgeState();
}

class _VerifiedBadgeState extends State<VerifiedBadge> {
  late final Future<bool> _verified = ProApi.isVerified(widget.ownerId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _verified,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        const blue = Color(0xFF1D7FD8);
        return Tooltip(
          message: 'Identité vérifiée par COTIZI',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, color: blue, size: widget.large ? 20 : 16),
              const SizedBox(width: 3),
              Text(
                'Vérifié',
                style: TextStyle(
                  color: blue,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.large ? 14 : 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================ Comptabilité

class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  late Future<ProData> _data = ProApi.load();
  DateTime? _month;

  void _reload() => setState(() => _data = ProApi.load());

  Future<void> _addExpense() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _ExpenseDialog(),
    );
    if (added == true) _reload();
  }

  Future<void> _deleteExpense(LedgerLine l) async {
    if (!await confirm(
      context,
      title: 'Supprimer la dépense',
      message: 'Supprimer « ${l.label} » (${money(-l.amount)}) ?',
      confirmLabel: 'Supprimer',
    )) {
      return;
    }
    try {
      await ProApi.deleteExpense(l.expenseId!);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pdf(Accounting a) async {
    try {
      final results = await Future.wait([
        Api.myProfile(),
        Api.business(Api.uid),
      ]);
      await shareAccounting(
        accounting: a,
        ownerName: (results[0] as Profile?)?.fullName ?? '',
        business: results[1] as Business?,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return Scaffold(
      appBar: AppBar(title: const Text('Comptabilité')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une dépense'),
      ),
      body: FutureView<ProData>(
        future: _data,
        onRetry: _reload,
        builder: (context, d) {
          final months = d.months;
          final month = _month ?? months.first;
          final a = d.month(month);
          Widget row(
            String label,
            int value, {
            Color? color,
            bool bold = false,
          }) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: bold
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : null,
                  ),
                ),
                Text(
                  _signed(value),
                  style: TextStyle(
                    color: color,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final m in months)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_monthLabel(m)),
                            selected: m == month,
                            onSelected: (_) => setState(() => _month = m),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bénéfice de ${_monthLabel(month).toLowerCase()}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _signed(a.profit),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: a.profit < 0 ? bad : null,
                          ),
                        ),
                        Text(
                          'Commissions + pénalités − dépenses',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mouvements d\'argent',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        row('Reçu des clients', a.received, color: good),
                        if (a.penalties > 0)
                          row('  dont pénalités', a.penalties),
                        row('Cagnottes remises', -a.paidOut, color: bad),
                        row(
                          'Carnets remis ou remboursés',
                          -a.carnetsPaid,
                          color: bad,
                        ),
                        row('Dépenses', -a.expenses, color: bad),
                        const Divider(),
                        row('Solde du mois', a.balance, bold: true),
                        const SizedBox(height: 10),
                        Text(
                          'Vos gains',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        row('Commissions gagnées', a.commissions, color: good),
                        row('Pénalités encaissées', a.penalties, color: good),
                        row('Dépenses', -a.expenses, color: bad),
                        const Divider(),
                        row('Bénéfice', a.profit, bold: true),
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pdf(a),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Partager le relevé du mois (PDF)'),
                ),
                SectionTitle('Opérations (${a.lines.length})'),
                if (a.lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aucune opération ce mois-ci.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final l in a.lines)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (l.amount > 0 ? good : bad).withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: l.amount > 0 ? good : bad,
                        child: Icon(switch (l.kind) {
                          'cotisation' => Icons.south_west,
                          'depense' => Icons.receipt_long_outlined,
                          _ => Icons.north_east,
                        }),
                      ),
                      title: Text(l.label),
                      subtitle: Text('${l.detail}\n${dateShort(l.date)}'),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${l.amount > 0 ? '+ ' : '− '}${money(l.amount.abs())}',
                            style: TextStyle(
                              color: l.amount > 0 ? good : bad,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (l.expenseId != null)
                            InkWell(
                              onTap: () => _deleteExpense(l),
                              child: const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Supprimer',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog();

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'transport';
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ProApi.addExpense(
        label: _label.text,
        amount: int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        category: _category,
        date: _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle dépense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'À quoi a servi la dépense ?',
                hintText: 'Ex. Zémidjan pour la collecte',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Montant',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                for (final e in Expense.categories.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _category = v ?? 'autre'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(dateLong(_date)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ============================================================ Statistiques

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<ProStats> _data = ProApi.load().then(ProStats.of);

  void _reload() => setState(() => _data = ProApi.load().then(ProStats.of));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: FutureView<ProStats>(
        future: _data,
        onRetry: _reload,
        builder: (context, s) {
          final trend = s.trend;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FigureGrid([
                      Figure(
                        'Reçu depuis le début',
                        money(s.totalReceived),
                        caption: 'cotisations et cases validées',
                      ),
                      Figure(
                        'Commissions gagnées',
                        money(s.totalCommissions),
                        caption: 'depuis le début',
                      ),
                      Figure(
                        'Clients en cours',
                        '${s.clients}',
                        caption:
                            '${s.activeGroups} groupe(s), ${s.activeCarnets} carnet(s)',
                      ),
                      Figure(
                        'Clients à jour',
                        '${s.upToDatePercent} %',
                        caption: '${s.upToDate} sur ${s.clients} aujourd\'hui',
                      ),
                    ]),
                  ),
                ),
                const SectionTitle('Argent reçu par mois'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (trend != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, left: 4),
                            child: Row(
                              children: [
                                Icon(
                                  trend >= 0
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                  color: trend >= 0 ? good : bad,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${trend >= 0 ? '+' : ''}$trend % par '
                                    'rapport au mois dernier',
                                    style: TextStyle(
                                      color: trend >= 0 ? good : bad,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _BarChart(months: s.months),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Les plus réguliers'),
                if (s.regular.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Pas encore assez de paiements validés.'),
                  ),
                for (final c in s.regular)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.star_rounded, color: good),
                      title: Text(c.name),
                      subtitle: Text(c.where),
                      trailing: Text(
                        '${c.paid} paiement${c.paid > 1 ? 's' : ''}',
                        style: TextStyle(
                          color: good,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SectionTitle('À surveiller (en retard)'),
                if (s.watch.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Aucun client en retard aujourd\'hui.',
                      style: TextStyle(color: good),
                    ),
                  ),
                for (final c in s.watch)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: bad),
                      title: Text(c.name),
                      subtitle: Text(c.where),
                      trailing: Text(
                        '${c.late} en retard',
                        style: TextStyle(
                          color: bad,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Chiffres calculés à partir des paiements validés, des '
                  'remises et des carnets.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Barres des 6 derniers mois : argent reçu, avec la commission en dessous.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.months});

  final List<Accounting> months;

  String _short(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
    if (v >= 1000) return '${(v / 1000).round()} k';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = months.fold<int>(0, (m, a) => a.received > m ? a.received : m);
    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final a in months)
            Expanded(
              child: Semantics(
                label:
                    '${_monthLabel(a.month)} : ${money(a.received)} reçus, '
                    '${money(a.commissions)} de commissions',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _short(a.received),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: top == 0 ? 2 : 2 + 130 * a.received / top,
                        decoration: BoxDecoration(
                          color: a.month.month == DateTime.now().month
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.45),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('MMM', 'fr').format(a.month),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ========================================================== Badge vérifié

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late Future<(Verification?, bool)> _data = _load();
  String _idType = 'cni';
  (Uint8List, String)? _id;
  (Uint8List, String)? _selfie;
  bool _busy = false;

  static Future<(Verification?, bool)> _load() async {
    final results = await Future.wait([
      ProApi.myVerification(),
      ProApi.isVerified(Api.uid),
    ]);
    return (results[0] as Verification?, results[1] as bool);
  }

  Future<void> _pick(bool selfie, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1280,
        imageQuality: 65,
      );
      if (file == null) return;
      final photo = await ProApi.readPhoto(file);
      setState(() => selfie ? _selfie = photo : _id = photo);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ProApi.submitVerification(
        idType: _idType,
        idPhoto: _id!,
        selfie: _selfie!,
      );
      if (!mounted) return;
      showInfo(context, 'Demande envoyée. COTIZI vérifie vos photos.');
      setState(() {
        _id = null;
        _selfie = null;
        _data = _load();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photoBox(String title, String hint, bool selfie) {
    final theme = Theme.of(context);
    final photo = selfie ? _selfie : _id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            Text(hint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(photo.$1, height: 160, fit: BoxFit.cover),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pick(selfie, ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(photo == null ? 'Prendre la photo' : 'Reprendre'),
                ),
                TextButton(
                  onPressed: () => _pick(selfie, ImageSource.gallery),
                  child: const Text('Depuis la galerie'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Badge vérifié')),
      body: FutureView<(Verification?, bool)>(
        future: _data,
        onRetry: () => setState(() => _data = _load()),
        builder: (context, data) {
          final (v, verified) = data;
          final canSend = v == null || v.rejected;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                color: theme.colorScheme.primaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified, color: Color(0xFF1D7FD8), size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Le badge « Vérifié » montre à vos clients que COTIZI '
                          'a contrôlé votre identité. Il rassure avant de '
                          'rejoindre vos tontines. Il est visible tant que '
                          'votre plan Pro est actif.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (verified || (v?.approved ?? false))
                StatusCard(
                  icon: Icons.verified,
                  color: const Color(0xFF1D7FD8),
                  title: verified
                      ? 'Votre badge est actif'
                      : 'Identité vérifiée',
                  message: verified
                      ? 'Vos clients voient « Vérifié » à côté de votre nom.'
                      : 'Le badge s\'affichera dès que votre plan Pro sera '
                            'actif.',
                )
              else if (v?.pending ?? false)
                StatusCard(
                  icon: Icons.hourglass_top,
                  color: paymentStatusColor(PaymentStatus.pending),
                  title: 'Demande en cours d\'examen',
                  message:
                      'Envoyée le ${dateLong(v!.submittedAt)}. COTIZI vérifie '
                      'vos photos, vous aurez votre badge après validation.',
                )
              else if (v?.rejected ?? false)
                StatusCard(
                  icon: Icons.error_outline,
                  color: paymentStatusColor(PaymentStatus.rejected),
                  title: 'Demande refusée',
                  message:
                      '${v!.reason ?? ''}\nCorrigez et envoyez une nouvelle '
                      'demande.',
                ),
              if (canSend) ...[
                const SectionTitle('Votre pièce d\'identité'),
                DropdownButtonFormField<String>(
                  initialValue: _idType,
                  decoration: const InputDecoration(labelText: 'Type de pièce'),
                  items: [
                    for (final e in Verification.idTypes.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (t) => setState(() => _idType = t ?? 'cni'),
                ),
                const SizedBox(height: 8),
                _photoBox(
                  '1. Photo de la pièce',
                  'Le recto, bien lisible, sans reflet.',
                  false,
                ),
                _photoBox(
                  '2. Selfie avec la pièce',
                  'Votre visage et la pièce tenue à côté.',
                  true,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || _id == null || _selfie == null
                      ? null
                      : _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer ma demande'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Vos photos ne sont vues que par l\'équipe COTIZI et '
                        'sont effacées dès la décision.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ================================================ Administration : badges

/// Demandes de badge en attente (Administration).
class VerificationRequestsScreen extends StatefulWidget {
  const VerificationRequestsScreen({super.key});

  @override
  State<VerificationRequestsScreen> createState() =>
      _VerificationRequestsScreenState();
}

class _VerificationRequestsScreenState
    extends State<VerificationRequestsScreen> {
  late Future<List<Verification>> _data = ProApi.pendingVerifications();

  void _reload() => setState(() => _data = ProApi.pendingVerifications());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes de badge')),
      body: FutureView<List<Verification>>(
        future: _data,
        onRetry: _reload,
        builder: (context, list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune demande de badge en attente.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final v in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(v.fullName),
                  subtitle: Text(
                    '${v.phone} · ${v.idTypeLabel}\n'
                    'Envoyée le ${dateTime(v.submittedAt)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _VerificationReviewScreen(v),
                      ),
                    );
                    _reload();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VerificationReviewScreen extends StatefulWidget {
  const _VerificationReviewScreen(this.v);

  final Verification v;

  @override
  State<_VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<_VerificationReviewScreen> {
  late Future<List<Uint8List?>> _photos = _loadPhotos();

  Future<List<Uint8List?>> _loadPhotos() => Future.wait([
    ProApi.verificationPhoto(widget.v.userId, 'id'),
    ProApi.verificationPhoto(widget.v.userId, 'selfie'),
  ]);
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    String? reason;
    if (approve) {
      if (!await confirm(
        context,
        title: 'Donner le badge',
        message:
            'Le nom « ${widget.v.fullName} » correspond à la pièce et au '
            'selfie ? Les photos seront effacées.',
        confirmLabel: 'Donner le badge',
      )) {
        return;
      }
    } else {
      reason = await _askReason();
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      approve
          ? await ProApi.approveVerification(widget.v)
          : await ProApi.rejectVerification(widget.v, reason!);
      if (!mounted) return;
      showInfo(context, approve ? 'Badge donné.' : 'Demande refusée.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController(text: 'Photo illisible');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raison du refus'),
        content: TextField(
          controller: c,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Expliquez au tontinier quoi corriger',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => c.text.trim().length < 2
                ? null
                : Navigator.pop(context, c.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    return Scaffold(
      appBar: AppBar(title: Text(v.fullName)),
      body: FutureView<List<Uint8List?>>(
        future: _photos,
        onRetry: () => setState(() => _photos = _loadPhotos()),
        builder: (context, photos) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${v.phone} · ${v.idTypeLabel}'),
            for (final (i, title) in [
              (0, 'Pièce d\'identité'),
              (1, 'Selfie avec la pièce'),
            ]) ...[
              SectionTitle(title),
              if (photos[i] == null)
                const Text('Photo absente.')
              else
                InteractiveViewer(maxScale: 5, child: Image.memory(photos[i]!)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _decide(true),
              icon: const Icon(Icons.verified),
              label: const Text('Donner le badge'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide(false),
              icon: const Icon(Icons.close),
              label: const Text('Refuser'),
            ),
          ],
        ),
      ),
    );
  }
}
