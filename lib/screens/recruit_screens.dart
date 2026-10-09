import 'package:flutter/material.dart';

import '../api.dart';
import '../business.dart';
import '../format.dart';
import '../models.dart';
import '../recruit.dart';
import '../settings.dart';
import '../widgets/common.dart';
import '../widgets/trust.dart';
import 'company_screens.dart';
import 'pro_screens.dart' show VerifiedBadge;
import 'subscription_screens.dart';

typedef _Space = (bool, List<Job>, List<JobApplication>, Company?);

/// Espace recrutement : offres d'emploi des entreprises, réservées aux
/// tontiniers Pro ; les entreprises y gèrent leurs offres.
class RecruitmentScreen extends StatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  State<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends State<RecruitmentScreen> {
  late Future<_Space> _data = _load();

  static Future<_Space> _load() async {
    final results = await Future.wait([
      Api.reloadProfile(),
      Api.isAdmin(),
      BusinessApi.myCompany(),
    ]);
    final profile = results[0] as Profile;
    final admin = results[1] as bool;
    final allowed = admin
        ? adminPlanView.value != 'free'
        : profile.isProAt(DateTime.now());
    if (!allowed) return (false, <Job>[], <JobApplication>[], null);
    final more = await Future.wait([
      RecruitApi.openJobs(),
      RecruitApi.myApplications(),
    ]);
    return (
      true,
      more[0] as List<Job>,
      more[1] as List<JobApplication>,
      results[2] as Company?,
    );
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Espace recrutement')),
      body: FutureView<_Space>(
        future: _data,
        onRetry: _reload,
        builder: (context, data) {
          final (allowed, jobs, mine, company) = data;
          if (!allowed) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const StatusCard(
                  icon: Icons.workspace_premium_outlined,
                  color: Color(0xFF0B7A5A),
                  title: 'Réservé aux tontiniers Pro',
                  message:
                      'Les entreprises de tontine recrutent des tontiniers '
                      'sérieux. Passez à Pro pour voir leurs offres et '
                      'postuler.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _open(const SubscriptionScreen()),
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('Passer à Pro'),
                ),
              ],
            );
          }
          final applied = {for (final a in mine) a.jobId: a};
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.work_outline, size: 30),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Des entreprises de tontine cherchent des '
                            'tontiniers Pro. Postulez : votre note de '
                            'confiance et votre badge vérifié comptent.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (company != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text(
                        'Gérer mes offres',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('Recruter pour ${company.name}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(MyJobsScreen(company: company)),
                    ),
                  ),
                if (mine.isNotEmpty) ...[
                  SectionTitle('Mes candidatures (${mine.length})'),
                  for (final a in mine)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          a.status == 'accepted'
                              ? Icons.check_circle
                              : a.status == 'rejected'
                              ? Icons.cancel_outlined
                              : Icons.hourglass_top,
                          color: _statusColor(a.status),
                        ),
                        title: Text(a.jobTitle),
                        subtitle: Text(
                          a.status == 'accepted'
                              ? '${a.companyName} vous a retenu : entrez son '
                                    'code d\'équipe dans Mon entreprise.'
                              : '${a.companyName} · ${dateShort(a.createdAt)}',
                        ),
                        trailing: StatusChip(
                          a.statusLabel,
                          _statusColor(a.status),
                        ),
                        onTap: a.status == 'accepted'
                            ? () => _open(const EnterpriseScreen())
                            : null,
                      ),
                    ),
                ],
                SectionTitle('Offres d\'emploi (${jobs.length})'),
                if (jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aucune offre pour le moment. Revenez bientôt.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final j in jobs)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      title: Text(
                        j.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(j.companyName)),
                              const SizedBox(width: 6),
                              VerifiedBadge(ownerId: j.bossId),
                            ],
                          ),
                          Text(
                            [
                              if (j.city.isNotEmpty) j.city,
                              if (j.salary.isNotEmpty) j.salary,
                            ].join(' · '),
                          ),
                        ],
                      ),
                      trailing: applied[j.id] != null
                          ? StatusChip(
                              applied[j.id]!.statusLabel,
                              _statusColor(applied[j.id]!.status),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () =>
                          _open(JobScreen(job: j, application: applied[j.id])),
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

Color _statusColor(String status) => switch (status) {
  'accepted' => paymentStatusColor(PaymentStatus.approved),
  'rejected' => paymentStatusColor(PaymentStatus.rejected),
  _ => paymentStatusColor(PaymentStatus.pending),
};

/// Détail d'une offre et candidature.
class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.job, this.application});

  final Job job;
  final JobApplication? application;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  late JobApplication? _application = widget.application;
  bool _busy = false;

  Future<void> _apply() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _ApplyDialog(),
    );
    if (message == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await RecruitApi.apply(widget.job, message);
      final mine = await RecruitApi.myApplications();
      if (!mounted) return;
      setState(
        () => _application = mine
            .where((a) => a.jobId == widget.job.id)
            .firstOrNull,
      );
      showInfo(context, 'Candidature envoyée à ${widget.job.companyName}.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    if (!await confirm(
      context,
      title: 'Retirer ma candidature',
      message: 'L\'entreprise ne la verra plus.',
      confirmLabel: 'Retirer',
    )) {
      return;
    }
    try {
      await RecruitApi.withdraw(_application!);
      if (mounted) setState(() => _application = null);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final j = widget.job;
    final a = _application;
    return Scaffold(
      appBar: AppBar(title: const Text('Offre d\'emploi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            j.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  j.companyName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              VerifiedBadge(ownerId: j.bossId, large: true),
            ],
          ),
          const SizedBox(height: 12),
          if (j.city.isNotEmpty) InfoRow('Lieu', j.city),
          if (j.salary.isNotEmpty) InfoRow('Salaire', j.salary),
          InfoRow('Publiée le', dateLong(j.createdAt)),
          const SectionTitle('Le travail'),
          Text(j.description, style: theme.textTheme.bodyLarge),
          const SectionTitle('L\'entreprise'),
          TrustCard(ownerId: j.bossId, ownerName: j.companyName),
          const SizedBox(height: 16),
          if (a == null)
            FilledButton.icon(
              onPressed: _busy ? null : _apply,
              icon: const Icon(Icons.send),
              label: const Text('Postuler'),
            )
          else ...[
            StatusCard(
              icon: a.status == 'accepted'
                  ? Icons.check_circle
                  : Icons.hourglass_top,
              color: _statusColor(a.status),
              title: 'Candidature ${a.statusLabel.toLowerCase()}',
              message: a.status == 'accepted'
                  ? 'L\'entreprise va vous envoyer son code d\'équipe : '
                        'entrez-le dans Profil → Mon entreprise.'
                  : a.status == 'rejected'
                  ? 'L\'entreprise n\'a pas retenu votre candidature.'
                  : 'Envoyée le ${dateLong(a.createdAt)}. L\'entreprise vous '
                        'répondra.',
            ),
            if (a.status == 'sent')
              TextButton(
                onPressed: _withdraw,
                child: const Text('Retirer ma candidature'),
              ),
          ],
        ],
      ),
    );
  }
}

class _ApplyDialog extends StatefulWidget {
  const _ApplyDialog();

  @override
  State<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<_ApplyDialog> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Postuler'),
      content: TextField(
        controller: _message,
        maxLength: 500,
        minLines: 3,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Votre message à l\'entreprise',
          hintText: 'Ex. 3 ans d\'expérience, 40 clients au marché Dantokpa',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _message.text),
          child: const Text('Envoyer ma candidature'),
        ),
      ],
    );
  }
}

// ============================================================ Entreprise

/// Offres publiées par l'entreprise et candidatures reçues.
class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key, required this.company});

  final Company company;

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  late Future<(List<Job>, List<JobApplication>)> _data = _load();

  static Future<(List<Job>, List<JobApplication>)> _load() async {
    final r = await Future.wait([
      RecruitApi.myJobs(),
      RecruitApi.receivedApplications(),
    ]);
    return (r[0] as List<Job>, r[1] as List<JobApplication>);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _publish() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _JobDialog(company: widget.company),
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes offres d\'emploi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _publish,
        icon: const Icon(Icons.add),
        label: const Text('Publier une offre'),
      ),
      body: FutureView<(List<Job>, List<JobApplication>)>(
        future: _data,
        onRetry: _reload,
        builder: (context, data) {
          final (jobs, apps) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Text(
                'Vos offres sont vues par les tontiniers Pro de COTIZI. '
                'Acceptez un candidat, puis envoyez-lui le code de votre '
                'équipe.',
              ),
              const SizedBox(height: 8),
              if (jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucune offre publiée.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final j in jobs)
                Builder(
                  builder: (context) {
                    final mine = apps.where((a) => a.jobId == j.id).toList();
                    final fresh = mine.where((a) => a.status == 'sent').length;
                    return Card(
                      child: ListTile(
                        title: Text(
                          j.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${mine.length} candidature${mine.length > 1 ? 's' : ''}'
                          '${fresh > 0 ? ' · $fresh à traiter' : ''}',
                        ),
                        trailing: StatusChip(
                          j.open ? 'Ouverte' : 'Fermée',
                          j.open
                              ? paymentStatusColor(PaymentStatus.approved)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _ApplicantsScreen(
                                job: j,
                                applications: mine,
                                company: widget.company,
                              ),
                            ),
                          );
                          _reload();
                        },
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _JobDialog extends StatefulWidget {
  const _JobDialog({required this.company});

  final Company company;

  @override
  State<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends State<_JobDialog> {
  final _title = TextEditingController();
  late final _city = TextEditingController(text: widget.company.city);
  final _salary = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _salary.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await RecruitApi.publish(
        company: widget.company,
        title: _title.text,
        city: _city.text,
        salary: _salary.text,
        description: _description.text,
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
      title: const Text('Publier une offre'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Poste proposé',
                hintText: 'Ex. Collecteur de carnets',
              ),
            ),
            TextField(
              controller: _city,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Lieu'),
            ),
            TextField(
              controller: _salary,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Salaire proposé',
                hintText: 'Ex. 40 000 F + 10 % des commissions',
              ),
            ),
            TextField(
              controller: _description,
              maxLength: 1500,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description du travail',
                alignLabelWithHint: true,
              ),
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
          child: const Text('Publier'),
        ),
      ],
    );
  }
}

/// Candidats d'une offre : note de confiance, badge, réponse.
class _ApplicantsScreen extends StatefulWidget {
  const _ApplicantsScreen({
    required this.job,
    required this.applications,
    required this.company,
  });

  final Job job;
  final List<JobApplication> applications;
  final Company company;

  @override
  State<_ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<_ApplicantsScreen> {
  late Job _job = widget.job;
  late List<JobApplication> _apps = widget.applications;

  Future<void> _answer(JobApplication a, bool accept) async {
    try {
      await RecruitApi.answer(a, accept);
      setState(() {
        _apps = [
          for (final x in _apps)
            x.id == a.id
                ? JobApplication(
                    id: x.id,
                    jobId: x.jobId,
                    jobTitle: x.jobTitle,
                    bossId: x.bossId,
                    companyName: x.companyName,
                    userId: x.userId,
                    fullName: x.fullName,
                    phone: x.phone,
                    message: x.message,
                    status: accept ? 'accepted' : 'rejected',
                    createdAt: x.createdAt,
                  )
                : x,
        ];
      });
      if (accept && mounted) await _sendCode(a);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sendCode(JobApplication a) => openWhatsApp(
    context,
    a.phone,
    'Bonjour ${a.fullName}, ${widget.company.name} a retenu votre '
    'candidature pour « ${_job.title} ».\n'
    'Pour rejoindre notre équipe : COTIZI → Profil → Mon entreprise, '
    'puis entrez le code : ${widget.company.inviteCode}',
  );

  Future<void> _toggle() async {
    try {
      await RecruitApi.setOpen(_job, !_job.open);
      setState(
        () => _job = Job(
          id: _job.id,
          bossId: _job.bossId,
          companyName: _job.companyName,
          title: _job.title,
          city: _job.city,
          salary: _job.salary,
          description: _job.description,
          open: !_job.open,
          createdAt: _job.createdAt,
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_job.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _job.open
                      ? 'Offre ouverte : visible des tontiniers Pro'
                      : 'Offre fermée : plus visible',
                ),
              ),
              TextButton(
                onPressed: _toggle,
                child: Text(_job.open ? 'Fermer l\'offre' : 'Rouvrir'),
              ),
            ],
          ),
          SectionTitle('Candidats (${_apps.length})'),
          if (_apps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune candidature pour le moment.'),
            ),
          for (final a in _apps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.fullName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        StatusChip(a.statusLabel, _statusColor(a.status)),
                      ],
                    ),
                    VerifiedBadge(ownerId: a.userId),
                    Text('${a.phone} · ${dateShort(a.createdAt)}'),
                    if (a.message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('« ${a.message} »'),
                    ],
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Voir sa note de confiance'),
                      children: [TrustCard(ownerId: a.userId)],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (a.status != 'accepted')
                          FilledButton(
                            onPressed: () => _answer(a, true),
                            child: const Text('Accepter'),
                          ),
                        if (a.status == 'sent')
                          OutlinedButton(
                            onPressed: () => _answer(a, false),
                            child: const Text('Refuser'),
                          ),
                        if (a.status == 'accepted')
                          OutlinedButton.icon(
                            onPressed: () => _sendCode(a),
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('Renvoyer le code d\'équipe'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
