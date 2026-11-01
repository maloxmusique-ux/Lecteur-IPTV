import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/i18n.dart';
import '../services/proxy.dart';
import '../state/settings.dart';

/// Reglage de la connexion protegee : l'utilisateur entre les informations
/// de son propre fournisseur VPN. Canalix ne fournit aucun VPN.
class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});

  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  late bool _on = ProxyBridge.config.enabled;
  late ProxyKind _kind = ProxyBridge.config.kind;
  late final _host = TextEditingController(text: ProxyBridge.config.host);
  late final _port = TextEditingController(text: '${ProxyBridge.config.port}');
  late final _user = TextEditingController(text: ProxyBridge.config.user);
  late final _pass = TextEditingController(text: ProxyBridge.config.password);
  bool _hide = true;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  ProxyConfig get _config => ProxyConfig(
        enabled: _on,
        kind: _kind,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        user: _user.text.trim(),
        password: _pass.text,
      );

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final (direct, vpn) = await ProxyBridge.testIp(_config);
      _ok = direct == null || direct != vpn;
      _result = _ok
          ? tr('vpn.testOk', [vpn, direct ?? '?'])
          : tr('vpn.testSame', [vpn]);
    } catch (e) {
      _ok = false;
      _result = tr('vpn.testFail', ['$e'.replaceFirst(RegExp(r'^\w+Exception: ?'), '')]);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final c = _config;
    if (c.enabled && !c.usable) {
      setState(() {
        _ok = false;
        _result = tr('vpn.missing');
      });
      return;
    }
    await ProxyBridge.save(c);
    if (!mounted) return;
    // Le lecteur reprend les reglages (adresse du relais).
    context.read<Settings>().update((_) {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(c.enabled ? tr('vpn.savedOn') : tr('vpn.savedOff'))));
    if (c.enabled) await _test();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = _on;
    return Scaffold(
      appBar: AppBar(title: Text(tr('vpn.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(tr('vpn.intro'), style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(tr('vpn.notOurs'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _on,
            onChanged: (v) => setState(() => _on = v),
            title: Text(tr('vpn.enable')),
            subtitle: Text(tr('vpn.enableSub')),
          ),
          if (fields) ...[
            const SizedBox(height: 8),
            SegmentedButton<ProxyKind>(
              segments: const [
                ButtonSegment(value: ProxyKind.socks5, label: Text('SOCKS5')),
                ButtonSegment(value: ProxyKind.http, label: Text('HTTP / HTTPS')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() {
                _kind = v.first;
                if (_port.text == '1080' && _kind == ProxyKind.http) _port.text = '8080';
                if (_port.text == '8080' && _kind == ProxyKind.socks5) _port.text = '1080';
              }),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  decoration: InputDecoration(
                      labelText: tr('vpn.server'),
                      hintText: 'ca-montreal.monvpn.com',
                      border: const OutlineInputBorder()),
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _port,
                  decoration: InputDecoration(
                      labelText: tr('vpn.port'), border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                  labelText: tr('vpn.user'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _hide,
              decoration: InputDecoration(
                labelText: tr('vpn.password'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(tr('vpn.where'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(tr('vpn.save')),
              ),
            ),
            if (fields) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded),
                  label: Text(tr('vpn.test')),
                ),
              ),
            ],
          ]),
          if (_result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_ok ? Colors.green : Colors.redAccent).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: (_ok ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.6)),
              ),
              child: Row(children: [
                Icon(_ok ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
                    color: _ok ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(child: Text(_result!)),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_outlined),
            title: Text(tr('vpn.systemTitle')),
            subtitle: Text(tr('vpn.systemText')),
            trailing: Platform.isWindows ? const Icon(Icons.open_in_new_rounded) : null,
            onTap: Platform.isWindows
                ? () => launchUrl(Uri.parse('ms-settings:network-vpn'))
                : null,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cast_rounded),
            title: Text(tr('vpn.castNote')),
          ),
        ],
      ),
    );
  }
}
