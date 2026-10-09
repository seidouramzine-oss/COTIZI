import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../invite_link.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/trust.dart';
import 'carnet_screens.dart';
import 'dashboard_screens.dart';
import 'group_screens.dart';
import 'profile_screens.dart';
import 'subscription_screens.dart';
import 'tontine_screens.dart';

/// Page d'un onglet qui sait se recharger quand on y revient.
mixin Reloadable<T extends StatefulWidget> on State<T> {
  void reload();

  /// Ouvre un écran puis recharge la page au retour.
  Future<void> open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) reload();
  }

  /// Ouvre un écran de création si l'essai ou l'abonnement est en cours.
  Future<void> openIfCanCreate(Widget screen) async {
    if (await checkCanCreate(context) && mounted) await open(screen);
  }
}

/// Coque de l'application : barre de navigation en bas.
/// Tontinier : Accueil, Mes tontines, Je participe, Profil.
/// Client (inscrit avec un code d'invitation) : Accueil, Mes tontines, Profil.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Profile _profile = widget.profile;
  int _index = 0;
  final _keys = List.generate(4, (_) => GlobalKey());

  /// Pages côte à côte : on glisse le doigt pour changer d'onglet (comme
  /// WhatsApp), ou on touche la barre du bas.
  final _pager = PageController();

  bool get _isMember => _profile.isMember;

  /// Onglet de la liste des participations.
  int get _participationsTab => _isMember ? 1 : 2;

  @override
  void initState() {
    super.initState();
    pendingInvite.addListener(_handleInvite);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleInvite());
  }

  @override
  void dispose() {
    pendingInvite.removeListener(_handleInvite);
    _pager.dispose();
    super.dispose();
  }

  /// Onglet touché dans la barre (ou ouvert par l'application) : la page
  /// glisse jusqu'à lui.
  void _select(int index) {
    if (index == _index) {
      _reloadPage(index);
      return;
    }
    if (!_pager.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients) _pager.jumpToPage(index);
      });
      return;
    }
    _pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Page affichée (après un glissement ou un toucher) : rechargée.
  void _onPageChanged(int index) {
    setState(() => _index = index);
    _reloadPage(index);
  }

  void _reloadPage(int index) {
    final state = _keys[index].currentState;
    if (state is Reloadable) state.reload();
  }

  /// Lien d'invitation reçu : rejoindre puis ouvrir le groupe ou le carnet.
  Future<void> _handleInvite() async {
    final code = pendingInvite.value;
    if (code == null || !mounted) return;
    pendingInvite.value = null;
    try {
      final (kind, id) = await Api.joinWithCode(code);
      if (!mounted) return;
      _select(_participationsTab);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => kind == 'group'
              ? GroupScreen(groupId: id)
              : CarnetScreen(carnetId: id),
        ),
      );
      if (mounted) _select(_participationsTab);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Clé de chaque page = sa position dans la barre (rechargement au retour)
    final profilePage = ProfilePage(
      key: _keys[_isMember ? 2 : 3],
      profile: _profile,
      onChanged: (p) => setState(() => _profile = p),
    );
    final pages = _isMember
        ? <Widget>[
            MemberDashboard(
              key: _keys[0],
              profile: _profile,
              onShowTontines: () => _select(1),
            ),
            ParticipationsPage(key: _keys[1], title: 'Mes tontines'),
            profilePage,
          ]
        : <Widget>[
            OwnerDashboard(
              key: _keys[0],
              profile: _profile,
              onShowTontines: () => _select(1),
            ),
            ManagedTontinesPage(key: _keys[1]),
            ParticipationsPage(key: _keys[2], title: 'Je participe'),
            profilePage,
          ];
    final destinations = _isMember
        ? const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Mes tontines',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings),
              label: 'Mes tontines',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Je participe',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ];
    return Scaffold(
      body: PageView(
        controller: _pager,
        onPageChanged: _onPageChanged,
        children: [for (final p in pages) _KeepAlive(child: p)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: destinations,
      ),
    );
  }
}

/// Garde une page en mémoire quand on glisse vers une autre (comme un
/// onglet de WhatsApp) : elle ne se recharge pas de zéro.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Tontines gérées par le tontinier.
class ManagedTontinesPage extends StatefulWidget {
  const ManagedTontinesPage({super.key});

  @override
  State<ManagedTontinesPage> createState() => _ManagedTontinesPageState();
}

class _ManagedTontinesPageState extends State<ManagedTontinesPage>
    with Reloadable {
  late Future<List<Tontine>> _tontines = Api.myTontines();

  @override
  void reload() => setState(() => _tontines = Api.myTontines());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes tontines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openIfCanCreate(const CreateTontineScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle tontine'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await _tontines;
        },
        child: FutureView<List<Tontine>>(
          future: _tontines,
          onRetry: reload,
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
                    leading: TypeAvatar(t.type),
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
                    onTap: () => open(TontineScreen(tontine: t)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groupes et carnets auxquels l'utilisateur participe.
class ParticipationsPage extends StatefulWidget {
  const ParticipationsPage({super.key, required this.title});

  final String title;

  @override
  State<ParticipationsPage> createState() => _ParticipationsPageState();
}

class _ParticipationsPageState extends State<ParticipationsPage>
    with Reloadable {
  late Future<(List<Group>, List<Carnet>)> _joined = _load();

  static Future<(List<Group>, List<Carnet>)> _load() async {
    final results = await Future.wait([Api.myGroups(), Api.myCarnets()]);
    return (results[0] as List<Group>, results[1] as List<Carnet>);
  }

  @override
  void reload() => setState(() => _joined = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(const JoinScreen()),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Rejoindre'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await _joined;
        },
        child: FutureView<(List<Group>, List<Carnet>)>(
          future: _joined,
          onRetry: reload,
          builder: (context, data) {
            final (groups, carnets) = data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (groups.isEmpty && carnets.isEmpty)
                  EmptyState(
                    icon: Icons.group_add_outlined,
                    title: 'Vous ne participez à aucune tontine',
                    message: 'Ouvrez le lien d\'invitation envoyé par votre tontinier, ou saisissez son code.',
                    action: FilledButton.icon(
                      onPressed: () => open(const JoinScreen()),
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
                      leading: const TypeAvatar(TontineType.cagnotte),
                      title: Text(
                        g.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${g.tontineName} · ${money(g.contributionAmount)} ${frequencyLabel(g.frequency).toLowerCase()}',
                      ),
                      trailing: StatusChip(
                        groupStatusLabel(g.status),
                        Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () => open(GroupScreen(groupId: g.id)),
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
                      leading: const TypeAvatar(TontineType.carnet),
                      title: Text(
                        c.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${c.tontineName} · ${money(c.caseAmount)} par case',
                          ),
                          const SizedBox(height: 6),
                          // Le texte « x / 31 cases payées » suffit aux lecteurs d'écran
                          ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: c.approvedCases / c.caseCount,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c.approvedCases} / ${c.caseCount} cases payées',
                          ),
                        ],
                      ),
                      onTap: () => open(CarnetScreen(carnetId: c.id)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class TypeAvatar extends StatelessWidget {
  const TypeAvatar(this.type, {super.key});

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

  /// Tontinier du code saisi : sa note de confiance s'affiche avant de
  /// rejoindre.
  String? _ownerId;

  Future<void> _check() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final (ownerId, _) = await Api.inviteOwner(_code.text);
      if (ownerId == Api.uid) {
        throw const AppException('C\'est votre propre code d\'invitation');
      }
      if (mounted) setState(() => _ownerId = ownerId);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
            decoration: const InputDecoration(
              labelText: 'Code d\'invitation',
              hintText: 'ABC123',
            ),
            onChanged: (_) {
              if (_ownerId != null) setState(() => _ownerId = null);
            },
            onSubmitted: (_) => _ownerId == null ? _check() : _join(),
          ),
          const SizedBox(height: 20),
          if (_ownerId != null) ...[
            TrustCard(key: ValueKey(_ownerId), ownerId: _ownerId!),
            const SizedBox(height: 4),
            const Text(
              'Vérifiez qu\'il s\'agit bien de votre tontinier avant de '
              'rejoindre. COTIZI ne touche jamais votre argent : vous le '
              'payez directement.',
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: _busy ? null : (_ownerId == null ? _check : _join),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_ownerId == null ? 'Vérifier le code' : 'Rejoindre'),
          ),
        ],
      ),
    );
  }
}
