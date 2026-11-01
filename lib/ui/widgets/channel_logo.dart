import 'package:flutter/material.dart';

/// Logo de chaine ou affiche, decode a la taille d'affichage
/// (cacheWidth) pour economiser memoire et CPU sur les longues listes.
class ChannelLogo extends StatelessWidget {
  final String url;
  final String name;
  final double width;
  final double height;
  final BoxFit fit;
  final double radius;

  const ChannelLogo({
    super.key,
    required this.url,
    required this.name,
    this.width = 44,
    this.height = 44,
    this.fit = BoxFit.contain,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = _Initials(name: name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: fit,
                cacheWidth: (width * dpr).round(),
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (_, child, frame, sync) => sync || frame != null
                    ? child
                    : placeholder,
              ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  const _Initials({required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letters = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    final hue = (name.hashCode % 360).abs().toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(1, hue, 0.35, 0.22).toColor(),
      ),
      child: Center(
        child: Text(
          letters,
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
