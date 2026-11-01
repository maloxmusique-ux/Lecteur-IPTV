import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'legal_screen.dart';
import 'settings_screen.dart';

/// Gestion des sources (playlists M3U et comptes Xtream).
class SourcesView extends StatelessWidget {
  /// Affichee seule (aucune source) : ajoute un acces aux reglages.
  final bool standalone;
  const SourcesView({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tab.sources')),
        actions: [
          if (standalone)
            IconButton(
              tooltip: tr('tab.settings'),
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsView())),
            ),
          IconButton(
            tooltip: tr('legal.title'),
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSourceEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('common.add')),
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
                    Text(tr('src.none'),
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      tr('src.noneHint'),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const LegalScreen())),
                      child: Text(tr('src.whereLegal')),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => showSourceEditor(context),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr('src.add')),
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
                      subtitle: Text(_subtitle(app, s)),
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
                                title: Text(tr('src.deleteQ')),
                                content: Text(s.name),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: Text(tr('common.cancel'))),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: Text(tr('common.delete'))),
                                ],
                              ),
                            );
                            if (ok == true) await app.removeSource(s);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Text(tr('common.edit'))),
                          PopupMenuItem(
                              value: 'refresh', child: Text(tr('common.refresh'))),
                          PopupMenuItem(
                              value: 'delete', child: Text(tr('common.delete'))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

String _subtitle(AppState app, Source s) {
  if (s.kind == SourceKind.m3u) return tr('src.m3u');
  final base = 'Xtream · ${s.username}';
  final a = app.active?.id == s.id ? app.account : null;
  if (a == null) return base;
  final parts = [base];
  if (a.expires != null) {
    final e = a.expires!;
    parts.add(tr('src.expires',
        ['${e.day} ${monthShort(e.month)} ${e.year}']));
  }
  if (a.maxConnections > 0) {
    parts.add(tr('src.connections', [a.maxConnections]));
  }
  return parts.join(' · ');
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
      setState(() => error = tr('src.mustCertify'));
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
          ? (kind == SourceKind.m3u ? tr('src.myPlaylist') : tr('src.myServer'))
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
      (v == null || v.trim().isEmpty) ? tr('common.required') : null;

  @override
  Widget build(BuildContext context) {
    final xtream = kind == SourceKind.xtream;
    return AlertDialog(
      title: Text(widget.existing == null ? tr('src.new') : tr('common.edit')),
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
                  decoration: InputDecoration(labelText: tr('src.name')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: url,
                  validator: _required,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: xtream ? tr('src.serverUrl') : tr('src.playlistUrl'),
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
                        InputDecoration(labelText: tr('src.username')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pass,
                    validator: _required,
                    obscureText: true,
                    decoration: InputDecoration(labelText: tr('src.password')),
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
                    label: Text(tr('src.advanced')),
                  ),
                ),
                if (advanced) ...[
                  TextFormField(
                    controller: epg,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: tr('src.epgUrl'),
                      helperText: tr('src.epgUrlHint'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ua,
                    decoration: InputDecoration(
                      labelText: tr('src.ua'),
                      helperText: tr('src.uaHint'),
                    ),
                  ),
                ],
                CheckboxListTile(
                  value: certified,
                  onChanged: (v) => setState(() => certified = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('src.certify')),
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
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('common.save')),
        ),
      ],
    );
  }
}
