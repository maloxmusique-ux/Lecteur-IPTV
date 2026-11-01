import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

const kLegalSummary =
    'StreamFlow est un lecteur multimédia. Il ne fournit, ne vend et ne '
    'référence aucune chaîne, playlist ou contenu.\n\n'
    'Tu es seul responsable des sources que tu ajoutes. Tu ne dois utiliser '
    'que des contenus auxquels tu as légalement le droit d\'accéder : '
    'abonnement officiel, flux diffusés gratuitement par leurs ayants droit, '
    'ou tes propres enregistrements.\n\n'
    'L\'utilisation de playlists ou de services diffusant des chaînes sans '
    'l\'autorisation des ayants droit est illégale (contrefaçon) et '
    'interdite dans StreamFlow.';

const kLegalSources = [
  (
    'Ton fournisseur d\'accès',
    'Certaines box proposent une playlist officielle de leurs chaînes TV, '
    'utilisable sur ton réseau local dans le cadre de ton abonnement.'
  ),
  (
    'Ton propre tuner TV (TNT)',
    'Un serveur comme TVHeadend ou Jellyfin avec un tuner TNT exporte une '
    'playlist M3U et un guide XMLTV des chaînes que tu reçois chez toi.'
  ),
  (
    'Les diffuseurs officiels',
    'Certaines chaînes publient elles-mêmes des flux gratuits et autorisés. '
    'Vérifie toujours que le lien vient du site officiel de la chaîne.'
  ),
  (
    'Ton fournisseur IPTV sous licence',
    'Un service légal qui détient les droits de diffusion et te fournit un '
    'accès M3U ou Xtream dans le cadre d\'un abonnement officiel.'
  ),
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
                Text('Bienvenue dans StreamFlow',
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
                  title: const Text(
                    'Je m\'engage à n\'utiliser que des contenus auxquels '
                    'j\'ai légalement accès.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _checked
                      ? () => context.read<AppState>().acceptLegal()
                      : null,
                  child: const Text('Accepter et continuer'),
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
      appBar: AppBar(title: const Text('Mentions légales')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(kLegalSummary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text('Sources légales possibles', style: theme.textTheme.titleMedium),
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
            'Si tu constates qu\'une source diffuse des contenus sans '
            'autorisation, supprime-la de l\'application.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
