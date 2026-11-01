import 'package:flutter/material.dart';

import '../../l10n/i18n.dart';
import '../../models/models.dart';
import 'channel_logo.dart';

/// Hauteur fixe : permet a ListView d'utiliser itemExtent (defilement O(1)).
const double kChannelTileHeight = 68;

class ChannelTile extends StatelessWidget {
  final Channel channel;
  final int? number;
  final bool selected;
  final bool favorite;
  final Programme? now;
  final int nowMs;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavorite;
  final bool autofocus;
  final bool recording;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    required this.nowMs,
    this.number,
    this.selected = false,
    this.favorite = false,
    this.now,
    this.onLongPress,
    this.onFavorite,
    this.autofocus = false,
    this.recording = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = now;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(12),
          focusColor: scheme.primary.withValues(alpha: 0.22),
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (number != null)
                  SizedBox(
                    width: 38,
                    child: Text(
                      '$number',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ChannelLogo(url: channel.logo, name: channel.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? scheme.primary : null,
                        ),
                      ),
                      if (p != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: p.progress(nowMs),
                            minHeight: 3,
                            backgroundColor:
                                scheme.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (recording)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.fiber_manual_record,
                        size: 14, color: Colors.redAccent),
                  ),
                if (channel.hasArchive)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.history_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                  ),
                if (onFavorite != null)
                  IconButton(
                    tooltip: favorite ? tr('fav.remove') : tr('fav.add'),
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      color: favorite ? Colors.amber : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte affiche pour films et series.
class PosterCard extends StatelessWidget {
  final Channel item;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Avancement de lecture (0..1), affiche en bas de l'affiche.
  final double? progress;
  final String? subtitle;

  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.favorite = false,
    this.onLongPress,
    this.progress,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        focusColor: theme.colorScheme.primary.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (_, c) => ChannelLogo(
                      url: item.logo,
                      name: item.name,
                      width: c.maxWidth,
                      height: c.maxHeight,
                      fit: BoxFit.cover,
                      radius: 0,
                    ),
                  ),
                  if (favorite)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.star_rounded, color: Colors.amber),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: subtitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
