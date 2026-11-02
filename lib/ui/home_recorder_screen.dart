import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../services/home_recorder.dart';
import 'navigation.dart';

/// Reglages > Enregistreur maison.
class HomeRecorderScreen extends StatefulWidget {
  const HomeRecorderScreen({super.key});

  @override
  State<HomeRecorderScreen> createState() => _HomeRecorderScreenState();
}

class _HomeRecorderScreenState extends State<HomeRecorderScreen> {
  bool _scanning = false;
  List<FoundRecorder>? _found;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _found = null;
    });
    final list = await HomeClient.scan();
    if (!mounted) return;
    final mine = context.read<HomeServer>();
    final own = await localIPv4();
    setState(() {
      _scanning = false;
      // On ne se propose pas soi-meme.
      _found = [
        for (final f in list)
          if (!(mine.enabled && own.contains(f.host))) f
      ];
    });
  }

  Future<void> _pair(String host, String name) async {
    final client = context.read<HomeClient>();
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('home.codeTitle', [name])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('home.codeHint')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 26, letterSpacing: 8),
              textAlign: TextAlign.center,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('home.connect'))),
        ],
      ),
    );
    if (code == null || code.length != 6 || !mounted) return;
    final ok = await client.pair(host, name, code);
    if (!mounted) return;
    toast(context, ok ? tr('home.paired', [name]) : tr('home.badCode'));
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('home.manual')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.1.20'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('common.ok'))),
        ],
      ),
    );
    if (ip == null || ip.trim().isEmpty || !mounted) return;
    await _pair(ip.trim(), ip.trim());
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch<HomeServer>();
    final client = context.watch<HomeClient>();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('home.title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(tr('home.intro'), style: theme.textTheme.bodyMedium),
          ),

          // ------------------------------------- Cet appareil enregistre
          if (HomeServer.supported) ...[
            section(tr('home.thisDevice')),
            SwitchListTile(
              secondary: const Icon(Icons.dns_rounded),
              title: Text(tr('home.serve')),
              subtitle: Text(tr(Platform.isAndroid
                  ? 'home.serveHintAndroid'
                  : Platform.isWindows
                      ? 'home.serveHintWindows'
                      : 'home.serveHintDesktop')),
              value: server.enabled,
              onChanged: (v) => server.setEnabled(v),
            ),
            if (server.enabled) ...[
              if (server.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(tr('home.serverError'),
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('home.yourCode'), style: muted),
                      const SizedBox(height: 4),
                      SelectableText(server.code,
                          style: theme.textTheme.displaySmall?.copyWith(
                              letterSpacing: 8, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(tr('home.nameLabel'), style: muted),
                      Text(server.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(tr('home.address'), style: muted),
                      Text(
                          server.addresses.isEmpty
                              ? tr('home.noNetwork')
                              : server.addresses.join('  ·  '),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: Text(tr('home.rename')),
                            onPressed: () async {
                              final ctrl =
                                  TextEditingController(text: server.name);
                              final v = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(tr('home.rename')),
                                  content: TextField(
                                      controller: ctrl,
                                      autofocus: true,
                                      onSubmitted: (v) =>
                                          Navigator.pop(ctx, v)),
                                  actions: [
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, ctrl.text),
                                        child: Text(tr('common.ok'))),
                                  ],
                                ),
                              );
                              if (v != null) server.setName(v);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(tr('home.newCode')),
                            onPressed: server.newCode,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(tr('home.serveTips'), style: muted),
              ),
            ],
          ],

          // ------------------------------- Enregistrer sur un autre appareil
          if (!server.enabled) ...[
            section(tr('home.useOther')),
            if (client.paired)
              ListTile(
                leading: Icon(
                    client.online
                        ? Icons.check_circle_rounded
                        : Icons.cloud_off_rounded,
                    color: client.online
                        ? Colors.greenAccent
                        : theme.colorScheme.error),
                title: Text(client.name),
                subtitle: Text(client.online
                    ? tr('home.online')
                    : client.error == 'code'
                        ? tr('home.badCode')
                        : tr('home.offline')),
                trailing: TextButton(
                  onPressed: client.forget,
                  child: Text(tr('home.forget')),
                ),
                onTap: client.refresh,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr('home.useOtherHint'), style: muted),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search_rounded),
                    label: Text(tr('home.search')),
                    onPressed: _scanning ? null : _scan,
                  ),
                  OutlinedButton(
                      onPressed: _manual, child: Text(tr('home.manual'))),
                ],
              ),
            ),
            if (_found != null && _found!.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(tr('home.noneFound'), style: muted),
              ),
            for (final f in _found ?? const <FoundRecorder>[])
              ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: Text(f.name),
                subtitle: Text(f.host),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pair(f.host, f.name),
              ),
          ],
        ],
      ),
    );
  }
}
