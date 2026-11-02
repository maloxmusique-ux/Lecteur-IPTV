import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../l10n/i18n.dart';
import '../player/player_engine.dart';
import '../services/eraser.dart';
import '../services/home_recorder.dart';
import '../services/license.dart';
import '../services/recorder.dart';
import 'legal_screen.dart';

void _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Reglages > A propos : mentions legales, documents, licences, et
/// suppression des donnees.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        );
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(label, style: muted)),
              Expanded(child: SelectableText(value)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('about.title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Image.asset('assets/icon/icon.png',
                width: 72, height: 72, cacheWidth: 216),
          ),
          const SizedBox(height: 10),
          Center(
              child: Text(Brand.fullName, style: theme.textTheme.titleLarge)),
          Center(
              child: Text(tr('about.version', [Brand.version]), style: muted)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(tr('about.what'),
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ),

          // ------------------------------------------- Mentions legales
          section(tr('about.legalNotice')),
          row(tr('about.publisher'), Brand.publisher),
          row(tr('about.location'), Brand.publisherLocation),
          row(tr('about.contact'), Brand.supportEmail),
          row(tr('about.site'), Brand.pages),
          row(tr('about.hosting'), tr('about.hostingValue')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(tr('about.noContent'), style: muted),
          ),

          // ------------------------------------------------- Documents
          section(tr('about.documents')),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('legal.privacy')),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _open(Brand.privacyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: Text(tr('legal.terms')),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _open(Brand.termsUrl),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(tr('legal.title')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(tr('about.support')),
            subtitle: Text(Brand.supportEmail),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _open(Brand.supportUrl),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: Text(tr('about.licenses')),
            subtitle: Text(tr('about.licensesSub')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: Brand.fullName,
              applicationVersion: Brand.version,
              applicationLegalese: '© ${DateTime.now().year} ${Brand.publisher}',
            ),
          ),

          // ------------------------------------------------- Mes donnees
          section(tr('about.myData')),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded,
                color: theme.colorScheme.error),
            title: Text(tr('erase.title'),
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: Text(tr('erase.sub')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeleteDataScreen())),
          ),
        ],
      ),
    );
  }
}

/// Suppression complete : serveur (licence, paiements lies) et appareil.
class DeleteDataScreen extends StatefulWidget {
  const DeleteDataScreen({super.key});

  @override
  State<DeleteDataScreen> createState() => _DeleteDataScreenState();
}

class _DeleteDataScreenState extends State<DeleteDataScreen> {
  bool _recordings = true;
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error),
        title: Text(tr('erase.confirmTitle')),
        content: Text(tr('erase.confirmText')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('erase.confirmButton')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final license = context.read<LicenseService>();
    final recorder = context.read<RecordingService>();
    final home = context.read<HomeServer>();
    final engine = context.read<PlayerEngine>();
    try {
      await license.deleteRemote();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('erase.offline');
        });
      }
      return;
    }
    try {
      await engine.stop();
    } catch (_) {}
    await DataEraser.eraseLocal(
        recorder: recorder, homeServer: home, recordings: _recordings);
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const _ErasedScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = Brand.storeBilling;
    Widget bullet(IconData i, String t) => ListTile(
          dense: true,
          leading: Icon(i, size: 20),
          title: Text(t),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('erase.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(tr('erase.intro'), style: theme.textTheme.bodyMedium),
          ),
          bullet(Icons.cloud_off_rounded, tr('erase.server')),
          bullet(Icons.playlist_remove_rounded, tr('erase.sources')),
          bullet(Icons.star_border_rounded, tr('erase.lists')),
          bullet(Icons.settings_backup_restore_rounded, tr('erase.settings')),
          CheckboxListTile(
            value: _recordings,
            onChanged: _busy ? null : (v) => setState(() => _recordings = v!),
            title: Text(tr('erase.recordings')),
            subtitle: Text(tr('erase.recordingsSub')),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.credit_card_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(tr('erase.subTitle'),
                            style: theme.textTheme.titleSmall)),
                  ]),
                  const SizedBox(height: 6),
                  Text(tr(store ? 'erase.subStore' : 'erase.subDirect')),
                  if (store) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(tr('erase.manageSub')),
                      onPressed: () => _open(Platform.isAndroid
                          ? 'https://play.google.com/store/account/subscriptions'
                          : 'https://apps.apple.com/account/subscriptions'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(tr('erase.kept'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_forever_rounded),
              label: Text(tr('erase.button')),
              onPressed: _busy ? null : _run,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fin : tout est efface. On ne revient pas dans l'app (son etat en
/// memoire n'existe plus sur l'appareil).
class _ErasedScreen extends StatelessWidget {
  const _ErasedScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Apple deconseille de fermer une app soi-meme : sur iPhone, on explique.
    final canClose = !Platform.isIOS;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 64, color: Colors.greenAccent),
                  const SizedBox(height: 16),
                  Text(tr('erase.doneTitle'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(tr(canClose ? 'erase.doneText' : 'erase.doneTextIos'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  if (canClose) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        if (Platform.isAndroid) {
                          SystemNavigator.pop();
                        } else {
                          exit(0);
                        }
                      },
                      child: Text(tr('erase.close')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
