import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../player/player_engine.dart';
import '../services/cast.dart';

/// Choix d'un Chromecast puis diffusion de la chaine ou du film en cours.
Future<void> showCastDialog(BuildContext context) async {
  final engine = context.read<PlayerEngine>();
  final c = engine.current;
  if (c == null) return;
  final d = await showDialog<CastDevice>(
    context: context,
    builder: (_) => const _CastPicker(),
  );
  if (d == null) return;
  await engine.player.pause();
  await CastSession.instance.play(d, c);
}

class _CastPicker extends StatefulWidget {
  const _CastPicker();

  @override
  State<_CastPicker> createState() => _CastPickerState();
}

class _CastPickerState extends State<_CastPicker> {
  List<CastDevice>? _devices;
  List<String> _otherTvs = const [];
  final _ip = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _devices = null);
    final scan = await scanForCast();
    if (mounted) {
      setState(() {
        _devices = scan.devices;
        _otherTvs = scan.otherTvs;
      });
    }
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(tr('cast.title')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (devices == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 14),
                    Text(tr('cast.searching')),
                  ],
                ),
              )
            else if (devices.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('cast.none')),
              ),
              if (_otherTvs.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  ),
                  child: Text(tr('cast.otherTvs', [_otherTvs.take(3).join(', ')])),
                ),
            ]
            else
              for (final d in devices)
                ListTile(
                  leading: const Icon(Icons.cast_rounded),
                  title: Text(d.name),
                  subtitle: Text(d.host),
                  onTap: () => Navigator.pop(context, d),
                ),
            const SizedBox(height: 12),
            Text(tr('cast.manual'), style: theme.textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ip,
                    decoration: const InputDecoration(
                        hintText: '192.168.1.50', isDense: true),
                    keyboardType: TextInputType.url,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final ip = _ip.text.trim();
                    if (ip.isEmpty) return;
                    Navigator.pop(context, CastDevice(ip, ip, 8009));
                  },
                  child: Text(tr('cast.connect')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(tr('cast.hint'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _search, child: Text(tr('common.refresh'))),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
      ],
    );
  }
}

/// Bandeau affiche dans le lecteur pendant la diffusion.
class CastBanner extends StatelessWidget {
  const CastBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CastSession.instance,
      builder: (context, _) {
        final s = CastSession.instance;
        if (s.state == CastState.idle) return const SizedBox.shrink();
        final err = s.state == CastState.error;
        final text = switch (s.state) {
          CastState.connecting => tr('cast.connecting', [s.device?.name ?? '']),
          CastState.error => s.error == 'media'
              ? tr('cast.unsupported')
              : tr('cast.failed'),
          _ => tr('cast.on', [s.device?.name ?? '']),
        };
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            color: (err ? Colors.red.shade900 : Colors.black).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(err ? Icons.error_outline_rounded : Icons.cast_connected_rounded,
                  color: Colors.white),
              const SizedBox(width: 12),
              Flexible(
                child: Text(text, style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              if (!err && s.state != CastState.connecting)
                IconButton(
                  color: Colors.white,
                  icon: Icon(s.state == CastState.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
                  onPressed: s.pauseResume,
                ),
              TextButton(
                onPressed: () {
                  s.stop();
                  context.read<PlayerEngine>().player.play();
                },
                child: Text(err ? tr('common.close') : tr('cast.stop')),
              ),
            ],
          ),
        );
      },
    );
  }
}
