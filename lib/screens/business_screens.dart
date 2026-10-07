import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'group_screens.dart';

/// Profil pro du tontinier : nom de l'activité, logo, numéros de paiement.
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _AccountRow {
  _AccountRow([PaymentAccount? a])
    : operator = a?.operator ?? mobileOperators.first,
      number = TextEditingController(text: a?.number ?? ''),
      holder = TextEditingController(text: a?.holder ?? '');

  String operator;
  final TextEditingController number;
  final TextEditingController holder;

  void dispose() {
    number.dispose();
    holder.dispose();
  }
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _contact = TextEditingController();
  final _accounts = <_AccountRow>[];
  String? _logo;
  String? _logoMime;
  late final Future<void> _loading = _load();
  bool _busy = false;

  Future<void> _load() async {
    final b = await Api.business(Api.uid);
    final me = await Api.myProfile();
    _name.text = b?.name ?? me?.fullName ?? '';
    _city.text = b?.city ?? '';
    _contact.text = b?.contactPhone ?? me?.phone ?? '';
    _logo = b?.logo;
    _logoMime = b?.logoMime;
    _accounts.addAll([for (final a in b?.accounts ?? []) _AccountRow(a)]);
    if (_accounts.isEmpty) _accounts.add(_AccountRow());
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _contact.dispose();
    for (final a in _accounts) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 70,
      );
      if (file == null) return;
      final (data, mime) = await Api.readLogo(file);
      setState(() {
        _logo = data;
        _logoMime = mime;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.saveBusiness(
        Business(
          ownerId: Api.uid,
          name: _name.text,
          city: _city.text,
          contactPhone: _contact.text,
          logo: _logo,
          logoMime: _logoMime,
          accounts: [
            for (final a in _accounts)
              PaymentAccount(
                operator: a.operator,
                number: a.number.text.trim(),
                holder: a.holder.text.trim(),
              ),
          ],
        ),
      );
      if (!mounted) return;
      showInfo(context, 'Profil pro enregistré');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil pro')),
      body: FutureView<void>(
        future: _loading,
        onRetry: () {},
        builder: (context, _) => Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Text(
                'Ces informations sont vues par vos clients : en haut de vos '
                'groupes, au moment de payer, sur les reçus et les relevés PDF.',
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage: _logo == null
                        ? null
                        : MemoryImage(base64.decode(_logo!)),
                    child: _logo == null
                        ? Icon(
                            Icons.add_a_photo_outlined,
                            color: scheme.primary,
                          )
                        : null,
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _pickLogo,
                  child: Text(
                    _logo == null ? 'Ajouter un logo' : 'Changer le logo',
                  ),
                ),
              ),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nom de votre activité',
                  hintText: 'Ex. Tontines Mama Awa',
                ),
                validator: (v) {
                  final n = (v ?? '').trim().length;
                  return n < 2 || n > 60 ? 'Entre 2 et 60 caractères' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Ville / quartier',
                ),
              ),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Numéro de contact (WhatsApp)',
                ),
              ),
              const SectionTitle('Mes numéros de paiement (Mobile Money)'),
              for (var i = 0; i < _accounts.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue:
                                    mobileOperators.contains(
                                      _accounts[i].operator,
                                    )
                                    ? _accounts[i].operator
                                    : mobileOperators.last,
                                decoration: const InputDecoration(
                                  labelText: 'Opérateur',
                                ),
                                items: [
                                  for (final o in mobileOperators)
                                    DropdownMenuItem(value: o, child: Text(o)),
                                ],
                                onChanged: (v) => _accounts[i].operator =
                                    v ?? _accounts[i].operator,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Supprimer ce numéro',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() {
                                _accounts.removeAt(i).dispose();
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _accounts[i].number,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Numéro',
                            hintText: '+229 01 97 00 00 00',
                          ),
                          validator: (v) =>
                              (v ?? '').trim().length > 30 ? 'Trop long' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _accounts[i].holder,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nom du titulaire (facultatif)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_accounts.length < 3)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _accounts.add(_AccountRow())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un numéro'),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tableau de bord des gains du tontinier.
class GainsScreen extends StatefulWidget {
  const GainsScreen({super.key});

  @override
  State<GainsScreen> createState() => _GainsScreenState();
}

class _GainsScreenState extends State<GainsScreen> {
  late Future<Gains> _data = Api.gains();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = paymentStatusColor(PaymentStatus.approved);
    final bad = paymentStatusColor(PaymentStatus.rejected);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes gains')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _data = Api.gains());
          await _data;
        },
        child: FutureView<Gains>(
          future: _data,
          onRetry: () => setState(() => _data = Api.gains()),
          builder: (context, g) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encaissé ce mois-ci',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        money(g.collectedThisMonth),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Paiements validés de vos groupes et carnets',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FigureGrid([
                    Figure(
                      'Commissions gagnées',
                      money(g.commissionsEarned),
                      caption: 'remises faites et carnets terminés',
                    ),
                    Figure(
                      'Commissions à venir',
                      money(g.commissionsUpcoming),
                      caption: 'tontines en cours',
                    ),
                    Figure('Pénalités encaissées', money(g.penaltiesCollected)),
                    Figure(
                      'En activité',
                      '${g.activeGroups} groupe${g.activeGroups > 1 ? 's' : ''}',
                      caption:
                          '${g.activeCarnets} carnet${g.activeCarnets > 1 ? 's' : ''} en cours',
                    ),
                  ]),
                ),
              ),
              StatusCard(
                icon: g.lateMembers == 0
                    ? Icons.check_circle
                    : Icons.warning_amber_rounded,
                color: g.lateMembers == 0 ? good : bad,
                title: g.lateMembers == 0
                    ? 'Aucun retard'
                    : '${money(g.lateAmount)} en retard',
                message: g.lateMembers == 0
                    ? 'Tous vos participants sont à jour.'
                    : '${g.lateMembers} participant${g.lateMembers > 1 ? 's' : ''} '
                          'en retard (pénalités comprises). Relancez-les depuis '
                          'leurs groupes.',
              ),
              const SectionTitle('Remises des 7 prochains jours'),
              if (g.upcomingPayouts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Aucune remise prévue.'),
                ),
              for (final (group, pot, date) in g.upcomingPayouts)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(
                      '${group.name} · cagnotte n°$pot',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${group.beneficiaryOf(pot)?.name ?? '—'} · '
                      '${money(group.netPot)} · ${countdownLabel(date)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupScreen(groupId: group.id),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
