import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// « Suggestions » : chaque utilisateur aide à améliorer COTIZI.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final _text = TextEditingController();
  String _kind = 'idee';
  bool _busy = false;
  late Future<List<Suggestion>> _mine = Api.mySuggestions();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await Api.sendSuggestion(_kind, _text.text);
      if (!mounted) return;
      _text.clear();
      FocusScope.of(context).unfocus();
      showInfo(context, 'Merci ! Votre suggestion est envoyée à COTIZI.');
      setState(() => _mine = Api.mySuggestions());
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
      appBar: AppBar(title: const Text('Suggestions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: theme.colorScheme.primary,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aidez-nous à améliorer COTIZI',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Une idée, un problème, quelque chose qui vous '
                          'manque pour gérer vos tontines ? Écrivez-le ici : '
                          'l\'équipe COTIZI lit chaque suggestion.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Votre suggestion'),
          Wrap(
            spacing: 8,
            children: [
              for (final e in Suggestion.kinds.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _kind == e.key,
                  onSelected: (_) => setState(() => _kind = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Votre suggestion',
              hintText:
                  'Ex. Pouvoir envoyer les rappels par SMS aux clients sans '
                  'smartphone',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('Envoyer ma suggestion'),
          ),
          FutureBuilder<List<Suggestion>>(
            future: _mine,
            builder: (context, snap) {
              final list = snap.data ?? const <Suggestion>[];
              if (list.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionTitle('Mes suggestions (${list.length})'),
                  for (final s in list)
                    Card(
                      child: ListTile(
                        title: Text(s.text),
                        subtitle: Text(
                          '${s.kindLabel} · ${dateTime(s.createdAt)}',
                        ),
                        trailing: StatusChip(
                          s.statusLabel,
                          s.status == 'done'
                              ? paymentStatusColor(PaymentStatus.approved)
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Administrateur : suggestions reçues de tous les utilisateurs.
class AdminSuggestionsScreen extends StatefulWidget {
  const AdminSuggestionsScreen({super.key});

  @override
  State<AdminSuggestionsScreen> createState() => _AdminSuggestionsScreenState();
}

class _AdminSuggestionsScreenState extends State<AdminSuggestionsScreen> {
  late Future<List<Suggestion>> _data = Api.allSuggestions();
  String _filter = 'all';

  void _reload() => setState(() => _data = Api.allSuggestions());

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Suggestions reçues')),
      body: FutureView<List<Suggestion>>(
        future: _data,
        onRetry: _reload,
        builder: (context, all) {
          final list = _filter == 'all'
              ? all
              : all.where((s) => s.status == _filter).toList();
          final fresh = all.where((s) => s.status == 'new').length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (key, label) in [
                    ('all', 'Toutes (${all.length})'),
                    ('new', 'Nouvelles ($fresh)'),
                    ('read', 'Lues'),
                    ('done', 'Prises en compte'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == key,
                      onSelected: (_) => setState(() => _filter = key),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucune suggestion pour le moment.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final s in list)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusChip(s.kindLabel, theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateTime(s.createdAt),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            if (s.status == 'new')
                              StatusChip(
                                'Nouvelle',
                                paymentStatusColor(PaymentStatus.pending),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(s.text, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 6),
                        Text(
                          '${s.fullName} · ${s.phone} · '
                          '${s.role == 'membre' ? 'Client' : 'Tontinier'}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (s.status != 'read')
                              TextButton(
                                onPressed: () => _act(
                                  () => Api.setSuggestionStatus(s.id, 'read'),
                                ),
                                child: const Text('Marquer lue'),
                              ),
                            if (s.status != 'done')
                              TextButton(
                                onPressed: () => _act(
                                  () => Api.setSuggestionStatus(s.id, 'done'),
                                ),
                                child: const Text('Prise en compte'),
                              ),
                            TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse(
                                  'https://wa.me/${s.phone.replaceAll(RegExp(r'\D'), '')}',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Text('Répondre (WhatsApp)'),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (await confirm(
                                  context,
                                  title: 'Supprimer',
                                  message: 'Supprimer cette suggestion ?',
                                  confirmLabel: 'Supprimer',
                                )) {
                                  await _act(() => Api.deleteSuggestion(s.id));
                                }
                              },
                              child: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
