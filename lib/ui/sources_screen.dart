import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import 'legal_screen.dart';

/// Gestion des sources (playlists M3U et comptes Xtream).
class SourcesView extends StatelessWidget {
  const SourcesView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          IconButton(
            tooltip: 'Mentions légales',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSourceEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: app.sources.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded,
                        size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Aucune source',
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                      'Ajoute une playlist M3U ou un compte Xtream Codes '
                      'auquel tu as légalement accès (abonnement officiel, '
                      'ton fournisseur d\'accès, ton propre tuner TV...).',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const LegalScreen())),
                      child: const Text('Où trouver des sources légales ?'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => showSourceEditor(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ajouter une source'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final s in app.sources)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        s.kind == SourceKind.m3u
                            ? Icons.playlist_play_rounded
                            : Icons.dns_rounded,
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        s.kind == SourceKind.m3u
                            ? 'Playlist M3U'
                            : 'Xtream · ${s.username}',
                      ),
                      selected: app.active?.id == s.id,
                      onTap: () => app.selectSource(s),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            showSourceEditor(context, existing: s);
                          } else if (v == 'refresh') {
                            await app.selectSource(s);
                            await app.refresh();
                          } else if (v == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Supprimer la source ?'),
                                content: Text(s.name),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Annuler')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Supprimer')),
                                ],
                              ),
                            );
                            if (ok == true) await app.removeSource(s);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Modifier')),
                          PopupMenuItem(
                              value: 'refresh', child: Text('Actualiser')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Supprimer')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

Future<void> showSourceEditor(BuildContext context, {Source? existing}) {
  return showDialog(
    context: context,
    builder: (_) => _SourceEditor(existing: existing),
  );
}

class _SourceEditor extends StatefulWidget {
  final Source? existing;
  const _SourceEditor({this.existing});

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late SourceKind kind = widget.existing?.kind ?? SourceKind.m3u;
  late final name = TextEditingController(text: widget.existing?.name);
  late final url = TextEditingController(text: widget.existing?.url);
  late final user = TextEditingController(text: widget.existing?.username);
  late final pass = TextEditingController(text: widget.existing?.password);
  late final epg = TextEditingController(text: widget.existing?.epgUrl);
  late final ua = TextEditingController(text: widget.existing?.userAgent);
  final _form = GlobalKey<FormState>();
  bool busy = false;
  bool advanced = false;
  late bool certified = widget.existing != null;
  String? error;

  @override
  void dispose() {
    for (final c in [name, url, user, pass, epg, ua]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!certified) {
      setState(() => error =
          'Tu dois certifier avoir légalement accès à cette source.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final app = context.read<AppState>();
    final s = Source(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.text.trim().isEmpty
          ? (kind == SourceKind.m3u ? 'Ma playlist' : 'Mon serveur')
          : name.text.trim(),
      kind: kind,
      url: url.text.trim(),
      username: user.text.trim(),
      password: pass.text,
      epgUrl: epg.text.trim(),
      userAgent: ua.text.trim(),
    );
    try {
      if (widget.existing == null) {
        await app.addSource(s);
      } else {
        await app.updateSource(s);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        busy = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    final xtream = kind == SourceKind.xtream;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nouvelle source' : 'Modifier'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.existing == null)
                  SegmentedButton<SourceKind>(
                    segments: const [
                      ButtonSegment(
                          value: SourceKind.m3u,
                          label: Text('M3U'),
                          icon: Icon(Icons.link_rounded)),
                      ButtonSegment(
                          value: SourceKind.xtream,
                          label: Text('Xtream Codes'),
                          icon: Icon(Icons.dns_rounded)),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => setState(() => kind = v.first),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: url,
                  validator: _required,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: xtream ? 'URL du serveur' : 'URL de la playlist',
                    hintText: xtream
                        ? 'http://serveur.exemple:8080'
                        : 'http://.../playlist.m3u',
                  ),
                ),
                if (xtream) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: user,
                    validator: _required,
                    decoration:
                        const InputDecoration(labelText: 'Nom d\'utilisateur'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pass,
                    validator: _required,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mot de passe'),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => advanced = !advanced),
                    icon: Icon(advanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded),
                    label: const Text('Options avancees'),
                  ),
                ),
                if (advanced) ...[
                  TextFormField(
                    controller: epg,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL du guide TV (XMLTV)',
                      helperText: 'Laisser vide pour la detection automatique',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ua,
                    decoration: const InputDecoration(
                      labelText: 'User-Agent personnalise',
                      helperText: 'Si ton fournisseur en exige un',
                    ),
                  ),
                ],
                CheckboxListTile(
                  value: certified,
                  onChanged: (v) => setState(() => certified = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Je certifie avoir légalement le droit d\'accéder aux '
                    'contenus de cette source.',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
