import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/i18n.dart';
import '../../player/player_engine.dart';
import '../../state/app_state.dart';

/// Explique clairement pourquoi la lecture bloque quand le fournisseur
/// IPTV refuse un ecran de plus (limite de connexions de l'abonnement).
class ConnectionLimitBanner extends StatelessWidget {
  const ConnectionLimitBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final failing = context.select<PlayerEngine, bool>((e) => e.lastError != null);
    if (!app.connectionsFull || !failing) return const SizedBox.shrink();
    final a = app.account;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.devices_other_rounded, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('conn.fullTitle'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    tr('conn.fullText', [a?.activeConnections ?? 0, a?.maxConnections ?? 0]),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
