import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/i18n.dart';
import '../models/profile.dart';
import '../state/app_state.dart';
import 'widgets/pin_dialog.dart';

const kProfileColors = [
  Color(0xFF3D7BFF),
  Color(0xFFE5484D),
  Color(0xFF30A46C),
  Color(0xFFF5A524),
  Color(0xFF8E4EC6),
  Color(0xFF12A594),
  Color(0xFFD6409F),
  Color(0xFF6E56CF),
];

Color profileColor(Profile p) =>
    kProfileColors[p.color % kProfileColors.length];

/// Choix et gestion des profils.
class ProfilesScreen extends StatefulWidget {
  /// Affiche au demarrage (pas de bouton retour).
  final bool startup;
  const ProfilesScreen({super.key, this.startup = false});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _manage = false;

  Future<void> _select(Profile p) async {
    final app = context.read<AppState>();
    if (_manage) {
      await _edit(p);
      return;
    }
    // Quitter un profil enfant demande le code parental.
    if (app.profile.kids && !p.kids && app.profileChosen && p.id != app.profileId) {
      if (!await askPin(context)) return;
    }
    await app.selectProfile(p);
    if (!widget.startup && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _edit(Profile? existing) async {
    final app = context.read<AppState>();
    if (app.parentalOn && !await askPin(context)) return;
    if (!mounted) return;
    final res = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _ProfileEditor(
        existing: existing,
        name: existing == null ? '' : app.profileName(existing),
      ),
    );
    if (res == null) return;
    if (res.delete && existing != null) {
      await app.deleteProfile(existing);
    } else if (res.profile != null) {
      await app.saveProfile(res.profile!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.startup
          ? null
          : AppBar(title: Text(tr('profile.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('profile.who'),
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final p in app.profiles)
                      _Avatar(
                        profile: p,
                        name: app.profileName(p),
                        selected: !widget.startup && p.id == app.profileId,
                        editing: _manage,
                        autofocus: p.id == app.profileId,
                        onTap: () => _select(p),
                      ),
                    if (_manage || app.profiles.length < 2)
                      _AddAvatar(onTap: () => _edit(null)),
                  ],
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _manage = !_manage),
                  icon: Icon(_manage ? Icons.check_rounded : Icons.edit_rounded),
                  label: Text(_manage ? tr('common.done') : tr('profile.manage')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Profile profile;
  final String name;
  final bool selected;
  final bool editing;
  final bool autofocus;
  final VoidCallback onTap;

  const _Avatar({
    required this.profile,
    required this.name,
    required this.selected,
    required this.editing,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = profileColor(profile);
    return InkWell(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 110,
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: profile.kids
                        ? const Icon(Icons.child_care_rounded,
                            size: 48, color: Colors.white)
                        : Text(
                            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                  ),
                  if (editing)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: Colors.white, size: 36),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
              if (profile.kids)
                Text(tr('profile.kids'),
                    style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAvatar extends StatelessWidget {
  final VoidCallback onTap;
  const _AddAvatar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 110,
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.add_rounded, size: 44),
              ),
              const SizedBox(height: 8),
              Text(tr('profile.add'),
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditResult {
  final Profile? profile;
  final bool delete;
  const _EditResult({this.profile, this.delete = false});
}

class _ProfileEditor extends StatefulWidget {
  final Profile? existing;
  final String name;
  const _ProfileEditor({required this.existing, required this.name});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.name);
  late int _color = widget.existing?.color ??
      DateTime.now().millisecond % kProfileColors.length;
  late bool _kids = widget.existing?.kids ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMain = widget.existing?.id == Profile.mainId;
    return AlertDialog(
      title: Text(widget.existing == null ? tr('profile.add') : tr('profile.edit')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('profile.name')),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < kProfileColors.length; i++)
                  InkWell(
                    onTap: () => setState(() => _color = i),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: kProfileColors[i],
                      child: i == _color
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            if (!isMain) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _kids,
                onChanged: (v) => setState(() => _kids = v),
                title: Text(tr('profile.kids')),
                subtitle: Text(tr('profile.kidsHint')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.existing != null && !isMain)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _EditResult(delete: true)),
            child: Text(tr('common.delete'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty && !isMain) return;
            final p = (widget.existing ??
                    Profile(
                      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
                      name: name,
                    ))
                .copyWith(name: name, color: _color, kids: _kids);
            Navigator.pop(context, _EditResult(profile: p));
          },
          child: Text(tr('common.save')),
        ),
      ],
    );
  }
}
