import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'carnet_screens.dart';
import 'group_screens.dart';
import 'tontine_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  late Future<List<Tontine>> _managed = Api.myTontines();
  late Future<(List<Group>, List<Carnet>)> _joined = _loadJoined();
  late final Future<Profile> _profile = Api.myProfile();

  static Future<(List<Group>, List<Carnet>)> _loadJoined() async {
    final results = await Future.wait([Api.myGroups(), Api.myCarnets()]);
    return (results[0] as List<Group>, results[1] as List<Carnet>);
  }

  void _reload() => setState(() {
    _managed = Api.myTontines();
    _joined = _loadJoined();
  });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _logout() async {
    if (await confirm(
      context,
      title: 'Déconnexion',
      message: 'Voulez-vous vous déconnecter ?',
      confirmLabel: 'Se déconnecter',
    )) {
      await Api.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Profile>(
          future: _profile,
          builder: (context, snap) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COTIZI',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              if (snap.hasData)
                Text(
                  'Bonjour ${snap.data!.fullName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.manage_accounts_outlined), text: 'Je gère'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Je participe'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _open(const CreateTontineScreen()),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle tontine'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _open(const JoinScreen()),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Rejoindre'),
            ),
      body: TabBarView(
        controller: _tabs,
        children: [_managedTab(), _joinedTab()],
      ),
    );
  }

  Widget _managedTab() {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _managed;
      },
      child: FutureView<List<Tontine>>(
        future: _managed,
        onRetry: _reload,
        builder: (context, tontines) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (tontines.isEmpty)
              const EmptyState(
                icon: Icons.savings_outlined,
                title: 'Aucune tontine',
                message: 'Créez votre première tontine à cagnotte ou à carnet, puis invitez vos membres.',
              ),
            for (final t in tontines)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: _TypeAvatar(t.type),
                  title: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    t.type == TontineType.cagnotte
                        ? 'Tontine à cagnotte · ${t.itemCount} groupe${t.itemCount > 1 ? 's' : ''}'
                        : 'Tontine à carnet · ${t.itemCount} carnet${t.itemCount > 1 ? 's' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(TontineScreen(tontine: t)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _joinedTab() {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _joined;
      },
      child: FutureView<(List<Group>, List<Carnet>)>(
        future: _joined,
        onRetry: _reload,
        builder: (context, data) {
          final (groups, carnets) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (groups.isEmpty && carnets.isEmpty)
                EmptyState(
                  icon: Icons.group_add_outlined,
                  title: 'Vous ne participez à aucune tontine',
                  message: 'Demandez le code d\'invitation à votre tontinier pour rejoindre un groupe ou un carnet.',
                  action: FilledButton.icon(
                    onPressed: () => _open(const JoinScreen()),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Rejoindre avec un code'),
                  ),
                ),
              if (groups.isNotEmpty)
                const SectionTitle('Mes groupes (cagnotte)'),
              for (final g in groups)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: const _TypeAvatar(TontineType.cagnotte),
                    title: Text(
                      g.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${g.tontine?.name ?? ''} · ${money(g.contributionAmount)} ${frequencyLabel(g.frequency).toLowerCase()}',
                    ),
                    trailing: StatusChip(
                      groupStatusLabel(g.status),
                      Theme.of(context).colorScheme.primary,
                    ),
                    onTap: () => _open(GroupScreen(groupId: g.id)),
                  ),
                ),
              if (carnets.isNotEmpty) const SectionTitle('Mes carnets'),
              for (final c in carnets)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: const _TypeAvatar(TontineType.carnet),
                    title: Text(
                      c.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.tontine?.name ?? ''} · ${money(c.caseAmount)} par case',
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: c.approvedCases / c.caseCount,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.approvedCases} / ${c.caseCount} cases payées',
                        ),
                      ],
                    ),
                    onTap: () => _open(CarnetScreen(carnetId: c.id)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TypeAvatar extends StatelessWidget {
  const _TypeAvatar(this.type);

  final TontineType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cagnotte = type == TontineType.cagnotte;
    return CircleAvatar(
      backgroundColor: cagnotte
          ? scheme.primaryContainer
          : scheme.tertiaryContainer,
      foregroundColor: cagnotte
          ? scheme.onPrimaryContainer
          : scheme.onTertiaryContainer,
      child: Icon(cagnotte ? Icons.savings_outlined : Icons.menu_book_outlined),
    );
  }
}

/// Rejoindre un groupe ou un carnet avec le code reçu du tontinier.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final (kind, id) = await Api.joinWithCode(_code.text);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => kind == 'group'
              ? GroupScreen(groupId: id)
              : CarnetScreen(carnetId: id),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Entrez le code d\'invitation envoyé par votre tontinier pour rejoindre son groupe ou votre carnet.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(hintText: 'ABC123'),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _join,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }
}
