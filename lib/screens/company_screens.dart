import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../business.dart';
import '../format.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'recruit_screens.dart';
import 'subscription_screens.dart';

String _monthLabel(DateTime m) {
  final s = DateFormat('MMMM yyyy', 'fr').format(m);
  return s[0].toUpperCase() + s.substring(1);
}

/// « Mon entreprise » : tableau de bord du patron (plan Business), fiche de
/// l'agent, ou choix entre rejoindre et créer une entreprise.
class EnterpriseScreen extends StatefulWidget {
  const EnterpriseScreen({super.key});

  @override
  State<EnterpriseScreen> createState() => _EnterpriseScreenState();
}

typedef _Hub = (Profile, Company?, (Company, Agent)?, bool);

class _EnterpriseScreenState extends State<EnterpriseScreen> {
  late Future<_Hub> _data = _load();

  static Future<_Hub> _load() async {
    final results = await Future.wait([
      Api.reloadProfile(),
      BusinessApi.myCompany(),
      BusinessApi.myEmployer(),
      Api.isAdmin(),
    ]);
    return (
      results[0] as Profile,
      results[1] as Company?,
      results[2] as (Company, Agent)?,
      results[3] as bool,
    );
  }

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Hub>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Mon entreprise')),
            body: Center(child: Text(errorMessage(snap.error!))),
          );
        }
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Mon entreprise')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final (profile, company, employer, admin) = snap.data!;
        // Administrateur : Business, sauf en mode test Gratuit ou Pro
        final business = admin
            ? const ['admin', 'business'].contains(adminPlanView.value)
            : profile.isBusinessAt(DateTime.now());
        if (business || (company != null && !admin)) {
          return _BossScreen(
            company: company,
            active: business,
            onChanged: _reload,
          );
        }
        if (employer != null) {
          return _AgentScreen(
            company: employer.$1,
            agent: employer.$2,
            onLeft: _reload,
          );
        }
        return _ChooseScreen(onChanged: _reload);
      },
    );
  }
}

// ================================================= Ni patron ni agent

class _ChooseScreen extends StatefulWidget {
  const _ChooseScreen({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_ChooseScreen> createState() => _ChooseScreenState();
}

class _ChooseScreenState extends State<_ChooseScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final c = await BusinessApi.join(_code.text);
      if (!mounted) return;
      showInfo(context, 'Vous faites partie de l\'équipe de ${c.name}.');
      widget.onChanged();
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
      appBar: AppBar(title: const Text('Mon entreprise')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.group_add_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Rejoindre une entreprise',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Vous travaillez pour une entreprise de tontine ? Entrez le '
                    'code que votre patron vous a donné. Il verra votre '
                    'activité et vous paiera votre salaire.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Code de l\'entreprise',
                      hintText: 'Ex. KZ7P4Q',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Rejoindre l\'équipe'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(
                Icons.business_center_outlined,
                color: theme.colorScheme.primary,
                size: 32,
              ),
              title: const Text(
                'Créer mon entreprise',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Vous avez des tontiniers qui travaillent pour vous ? Le plan '
                'Business vous permet de suivre leur activité et de calculer '
                'leurs salaires.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                );
                widget.onChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ Patron

class _BossScreen extends StatefulWidget {
  const _BossScreen({
    required this.company,
    required this.active,
    required this.onChanged,
  });

  final Company? company;

  /// Plan Business en cours.
  final bool active;
  final VoidCallback onChanged;

  @override
  State<_BossScreen> createState() => _BossScreenState();
}

class _BossScreenState extends State<_BossScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<CompanyMonth>? _data = widget.company == null
      ? null
      : BusinessApi.month(_month);

  void _reload() => setState(() => _data = BusinessApi.month(_month));

  Future<void> _edit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyDialog(initial: widget.company),
    );
    if (saved == true) widget.onChanged();
  }

  Future<void> _invite(Company c) async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Rejoignez l\'équipe de ${c.name} sur COTIZI.\n'
            'Dans COTIZI : Profil → Mon entreprise → Rejoindre une entreprise, '
            'puis entrez le code : ${c.inviteCode}',
      ),
    );
  }

  Future<void> _newCode(Company c) async {
    if (!await confirm(
      context,
      title: 'Nouveau code',
      message:
          'L\'ancien code ne marchera plus. Les agents déjà dans l\'équipe '
          'restent.',
      confirmLabel: 'Changer le code',
    )) {
      return;
    }
    try {
      await BusinessApi.saveCompany(
        name: c.name,
        city: c.city,
        phone: c.phone,
        newCode: true,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final theme = Theme.of(context);
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon entreprise')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const StatusCard(
              icon: Icons.business_center_outlined,
              color: Color(0xFF0B7A5A),
              title: 'Votre plan Business est actif',
              message:
                  'Créez votre entreprise, puis invitez vos tontiniers avec '
                  'son code. Vous suivrez leur activité et leurs salaires.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Créer mon entreprise'),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 6; i++) DateTime(now.year, now.month - i),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Modifier l\'entreprise',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!widget.active)
              StatusCard(
                icon: Icons.warning_amber_rounded,
                color: paymentStatusColor(PaymentStatus.pending),
                title: 'Plan Business terminé',
                message:
                    'Renouvelez-le pour suivre votre équipe et payer les '
                    'salaires. Vos agents gardent leurs groupes.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
              ),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code pour inviter un tontinier',
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(
                      c.inviteCode,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _invite(c),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Inviter un tontinier'),
                        ),
                        TextButton(
                          onPressed: () => _newCode(c),
                          child: const Text('Nouveau code'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text(
                  'Recruter des tontiniers',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Publier une offre vue par les tontiniers Pro',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.active
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MyJobsScreen(company: c),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
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
                        selected: m == _month,
                        onSelected: (_) {
                          _month = m;
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_data != null)
              FutureView<CompanyMonth>(
                future: _data!,
                onRetry: _reload,
                builder: (context, m) => _teamView(m),
              ),
          ],
        ),
      ),
    );
  }

  Widget _teamView(CompanyMonth m) {
    final good = paymentStatusColor(PaymentStatus.approved);
    final pending = paymentStatusColor(PaymentStatus.pending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FigureGrid([
              Figure(
                'Reçu par l\'équipe',
                money(m.received),
                caption: '${m.clients} clients en cours',
              ),
              Figure('Commissions', money(m.commissions)),
              Figure('Salaires', money(m.salaries)),
              Figure(
                'Bénéfice de l\'entreprise',
                money(m.profit),
                caption: 'commissions + pénalités − salaires',
              ),
            ]),
          ),
        ),
        SectionTitle('Mon équipe (${m.reports.length})'),
        if (m.reports.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Aucun tontinier dans l\'équipe. Envoyez-leur le code avec '
              '« Inviter un tontinier » : ils l\'entrent dans Profil → Mon '
              'entreprise.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final r in m.reports)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  r.agent.fullName.isEmpty ? '?' : r.agent.fullName[0],
                ),
              ),
              title: Text(
                r.agent.fullName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Reçu : ${money(r.month.received)} · '
                'Commissions : ${money(r.month.commissions)}\n'
                'Salaire : ${money(r.paid?.amount ?? r.salaryTotal)}',
              ),
              isThreeLine: true,
              trailing: StatusChip(
                r.paid != null ? 'Payé' : 'À payer',
                r.paid != null ? good : pending,
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        _AgentDetailScreen(report: r, active: widget.active),
                  ),
                );
                _reload();
              },
            ),
          ),
      ],
    );
  }
}

class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog({this.initial});

  final Company? initial;

  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _city = TextEditingController(text: widget.initial?.city);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await BusinessApi.saveCompany(
        name: _name.text,
        city: _city.text,
        phone: _phone.text,
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
      title: Text(
        widget.initial == null ? 'Créer mon entreprise' : 'Mon entreprise',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'entreprise',
                hintText: 'Ex. Tontines Express',
              ),
            ),
            TextField(
              controller: _city,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ville'),
            ),
            TextField(
              controller: _phone,
              maxLength: 30,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
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

/// Fiche d'un agent pour le patron : activité du mois et salaire.
class _AgentDetailScreen extends StatefulWidget {
  const _AgentDetailScreen({required this.report, required this.active});

  final AgentReport report;
  final bool active;

  @override
  State<_AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends State<_AgentDetailScreen> {
  late AgentReport _r = widget.report;
  bool _busy = false;

  Future<void> _refresh() async {
    final m = await BusinessApi.month(_r.month.month);
    final r = m.reports.where((x) => x.agent.id == _r.agent.id).firstOrNull;
    if (r != null && mounted) setState(() => _r = r);
  }

  Future<void> _editSalary() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SalaryDialog(agent: _r.agent),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _pay() async {
    final total = _r.salaryTotal;
    if (!await confirm(
      context,
      title: 'Salaire payé',
      message:
          'Avez-vous payé ${money(total)} à ${_r.agent.fullName} pour '
          '${_monthLabel(_r.month.month).toLowerCase()} ? Il le verra dans sa '
          'fiche de paie.',
      confirmLabel: 'Oui, payé',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await BusinessApi.paySalary(_r);
      await _refresh();
      if (mounted) showInfo(context, 'Salaire noté comme payé.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (!await confirm(
      context,
      title: 'Retirer de l\'équipe',
      message:
          '${_r.agent.fullName} ne fera plus partie de votre entreprise. Ses '
          'groupes et ses clients restent à lui.',
      confirmLabel: 'Retirer',
    )) {
      return;
    }
    try {
      await BusinessApi.removeAgent(_r.agent);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final a = r.month;
    final (fixed, commission) = r.salary;
    final good = paymentStatusColor(PaymentStatus.approved);
    return Scaffold(
      appBar: AppBar(title: Text(r.agent.fullName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '${r.agent.phone} · dans l\'équipe depuis le '
            '${dateLong(r.agent.joinedAt)}',
          ),
          SectionTitle('Activité de ${_monthLabel(a.month).toLowerCase()}'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FigureGrid([
                Figure('Reçu des clients', money(a.received)),
                Figure('Commissions', money(a.commissions)),
                Figure(
                  'Clients en cours',
                  '${r.stats.clients}',
                  caption:
                      '${r.stats.activeGroups} groupe(s), ${r.stats.activeCarnets} carnet(s)',
                ),
                Figure(
                  'Clients à jour',
                  '${r.stats.upToDatePercent} %',
                  caption: '${r.stats.watch.length} en retard',
                ),
              ]),
            ),
          ),
          const SectionTitle('Salaire'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(r.agent.salaryLabel),
                  const SizedBox(height: 8),
                  InfoRow('Fixe', money(r.paid?.fixed ?? fixed)),
                  InfoRow(
                    'Commission',
                    money(r.paid?.commission ?? commission),
                  ),
                  InfoRow(
                    'Salaire du mois',
                    money(r.paid?.amount ?? r.salaryTotal),
                    bold: true,
                  ),
                  const SizedBox(height: 8),
                  if (r.paid != null)
                    StatusCard(
                      icon: Icons.check_circle,
                      color: good,
                      title: 'Payé le ${dateLong(r.paid!.paidAt)}',
                    )
                  else if (widget.active)
                    FilledButton.icon(
                      onPressed: _busy ? null : _pay,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Noter le salaire comme payé'),
                    ),
                  if (widget.active)
                    TextButton.icon(
                      onPressed: _editSalary,
                      icon: const Icon(Icons.tune),
                      label: const Text('Régler le salaire'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _remove,
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Retirer de l\'équipe'),
          ),
        ],
      ),
    );
  }
}

class _SalaryDialog extends StatefulWidget {
  const _SalaryDialog({required this.agent});

  final Agent agent;

  @override
  State<_SalaryDialog> createState() => _SalaryDialogState();
}

class _SalaryDialogState extends State<_SalaryDialog> {
  late String _type = widget.agent.salaryType == 'none'
      ? 'mixed'
      : widget.agent.salaryType;
  late final _fixed = TextEditingController(
    text: widget.agent.fixed > 0 ? '${widget.agent.fixed}' : '',
  );
  late final _percent = TextEditingController(
    text: widget.agent.percent > 0
        ? widget.agent.percent.toStringAsFixed(
            widget.agent.percent == widget.agent.percent.roundToDouble()
                ? 0
                : 1,
          )
        : '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _fixed.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await BusinessApi.setSalary(
        widget.agent,
        type: _type,
        fixed: int.tryParse(_fixed.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        percent: double.tryParse(_percent.text.replaceAll(',', '.')) ?? 0,
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
    final withFixed = _type == 'fixed' || _type == 'mixed';
    final withPercent = _type == 'commission' || _type == 'mixed';
    return AlertDialog(
      title: Text('Salaire de ${widget.agent.fullName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v ?? 'mixed'),
              child: Column(
                children: [
                  for (final e in Agent.salaryTypes.entries.skip(1))
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: e.key,
                      title: Text(e.value),
                    ),
                ],
              ),
            ),
            if (withFixed)
              TextField(
                controller: _fixed,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Salaire fixe par mois',
                  suffixText: 'FCFA',
                ),
              ),
            if (withPercent) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _percent,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Part des commissions de l\'agent',
                  suffixText: '%',
                  helperText: 'Ex. 20 % des commissions de ses groupes',
                ),
              ),
            ],
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

// ================================================================= Agent

class _AgentScreen extends StatefulWidget {
  const _AgentScreen({
    required this.company,
    required this.agent,
    required this.onLeft,
  });

  final Company company;
  final Agent agent;
  final VoidCallback onLeft;

  @override
  State<_AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<_AgentScreen> {
  late final Future<List<Salary>> _salaries = BusinessApi.mySalaries(
    widget.company.bossId,
  );

  Future<void> _leave() async {
    if (!await confirm(
      context,
      title: 'Quitter l\'entreprise',
      message:
          'Vous ne ferez plus partie de ${widget.company.name}. Vos groupes '
          'et vos clients restent à vous.',
      confirmLabel: 'Quitter',
    )) {
      return;
    }
    try {
      await BusinessApi.leave(widget.company.bossId);
      widget.onLeft();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.company;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon entreprise')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.business_center, size: 32),
              title: Text(
                c.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  if (c.city.isNotEmpty) c.city,
                  if (c.phone.isNotEmpty) c.phone,
                  'Vous êtes dans l\'équipe',
                ].join(' · '),
              ),
            ),
          ),
          const SectionTitle('Mon salaire'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(widget.agent.salaryLabel),
              subtitle: const Text(
                'Réglé par votre patron. Vous avez aussi tout le plan Pro : '
                'aucune limite, comptabilité, statistiques.',
              ),
            ),
          ),
          const SectionTitle('Mes fiches de paie'),
          FutureView<List<Salary>>(
            future: _salaries,
            onRetry: () => setState(() {}),
            builder: (context, list) => Column(
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aucun salaire payé pour le moment.'),
                  ),
                for (final s in list)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.receipt_long_outlined,
                        color: paymentStatusColor(PaymentStatus.approved),
                      ),
                      title: Text(_monthLabel(s.monthDate)),
                      subtitle: Text(
                        'Fixe ${money(s.fixed)} + commission '
                        '${money(s.commission)}\nPayé le ${dateLong(s.paidAt)}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        money(s.amount),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            label: const Text('Quitter l\'entreprise'),
          ),
        ],
      ),
    );
  }
}
