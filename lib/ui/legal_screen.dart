import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../state/app_state.dart';
import '../state/settings.dart';

String get kLegalSummary => tr('legal.summary');

List<(String, String)> get kLegalSources => [
      (tr('legal.s1t'), tr('legal.s1d')),
      (tr('legal.s2t'), tr('legal.s2d')),
      (tr('legal.s3t'), tr('legal.s3d')),
      (tr('legal.s4t'), tr('legal.s4d')),
    ];

/// Ecran affiche au premier lancement : acceptation obligatoire.
class LegalGate extends StatefulWidget {
  const LegalGate({super.key});

  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: _LangButton(),
                ),
                Text(tr('legal.welcome'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(kLegalSummary, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _checked,
                  onChanged: (v) => setState(() => _checked = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('legal.commit')),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _checked
                      ? () => context.read<AppState>().acceptLegal()
                      : null,
                  child: Text(tr('legal.accept')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page de mentions legales et d'idees de sources legales.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('legal.title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(kLegalSummary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text(tr('legal.possible'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (title, desc) in kLegalSources)
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(title),
                subtitle: Text(desc),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            tr('legal.footer'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Choix de la langue des le premier ecran.
class _LangButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    return PopupMenuButton<String>(
      tooltip: tr('settings.language'),
      onSelected: (v) => s.update((x) => x.lang = v),
      itemBuilder: (_) => [
        for (final e in kLanguages.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 20),
            const SizedBox(width: 6),
            Text(kLanguages[s.effectiveLang] ?? ''),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}
