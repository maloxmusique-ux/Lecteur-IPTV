import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/brand.dart';
import '../l10n/i18n.dart';
import '../models/models.dart';
import '../services/backup.dart';
import '../services/recorder.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'legal_screen.dart';
import 'navigation.dart';
import 'player_screen.dart' show fitLabel;
import 'profiles_screen.dart';
import 'subscription_screen.dart';
import '../services/license.dart';
import '../services/proxy.dart';
import 'vpn_screen.dart';
import 'widgets/pin_dialog.dart';

/// Langues proposees pour l'audio et les sous-titres (code -> alias mpv).
const _mediaLangs = {
  'fr': 'fr,fre,fra,french,français',
  'en': 'en,eng,english',
  'es': 'es,spa,spanish,español',
  'pt': 'pt,por,portuguese,português',
  'ar': 'ar,ara,arabic',
  'it': 'it,ita,italian',
  'de': 'de,ger,deu,german',
  'ht': 'ht,hat,creole',
};

String _mediaLangName(String code) => switch (code) {
      'fr' => 'Français',
      'en' => 'English',
      'es' => 'Español',
      'pt' => 'Português',
      'ar' => 'العربية',
      'it' => 'Italiano',
      'de' => 'Deutsch',
      'ht' => 'Kreyòl',
      _ => code,
    };

String _codeOf(String aliases) =>
    aliases.isEmpty ? '' : aliases.split(',').first;

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    // Un profil enfant ne peut pas modifier les reglages sans le code.
    if (app.profile.kids && app.parentalOn && !app.unlocked) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('tab.settings'))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 56),
              const SizedBox(height: 12),
              Text(tr('settings.locked')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (await askPin(context)) app.unlock();
                },
                child: Text(tr('pin.enter')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ProfilesScreen())),
                child: Text(tr('profile.switch')),
              ),
            ],
          ),
        ),
      );
    }

    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        );

    Future<T?> pick<T>(String title, List<(T, String)> options, T current) =>
        showDialog<T>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              for (final (v, label) in options)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, v),
                  child: Row(
                    children: [
                      Icon(v == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label)),
                    ],
                  ),
                ),
            ],
          ),
        );

    final langOptions = <(String, String)>[
      ('auto', tr('settings.langAuto')),
      for (final e in kLanguages.entries) (e.key, e.value),
    ];
    final bufferOptions = <(BufferMode, String)>[
      (BufferMode.fast, tr('settings.bufFast')),
      (BufferMode.balanced, tr('settings.bufBalanced')),
      (BufferMode.stable, tr('settings.bufStable')),
    ];
    final qualityOptions = <(StreamQuality, String)>[
      (StreamQuality.best, tr('quality.best')),
      (StreamQuality.fhd, tr('quality.fhd')),
      (StreamQuality.hd, tr('quality.hd')),
      (StreamQuality.low, tr('quality.low')),
    ];
    final audioOptions = <(String, String)>[
      ('', tr('settings.langDefault')),
      for (final c in _mediaLangs.keys) (c, _mediaLangName(c)),
    ];
    final subOptions = <(String, String)>[
      ('', tr('settings.subsOff')),
      for (final c in _mediaLangs.keys) (c, _mediaLangName(c)),
    ];

    String label<T>(List<(T, String)> o, T v) =>
        o.firstWhere((e) => e.$1 == v, orElse: () => o.first).$2;

    return Scaffold(
      appBar: AppBar(title: Text(tr('tab.settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ------------------------------------------------- Abonnement
          section(tr('sub.title')),
          Builder(builder: (context) {
            final lic = context.watch<LicenseService>();
            final i = lic.info;
            return ListTile(
              leading: const Icon(Icons.workspace_premium_rounded),
              title: Text(tr('sub.title')),
              subtitle: Text(switch (i.status) {
                LicenseStatus.trial => tr('sub.trial', [i.trialDaysLeft]),
                LicenseStatus.active => i.plan == null
                    ? tr('sub.active')
                    : '${tr('sub.active')} · ${planName(i.plan!)}',
                LicenseStatus.expired => tr('sub.expired'),
              }),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen())),
            );
          }),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(tr('help.title')),
            subtitle: Text(tr('help.subtitle')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
          ListTile(
            leading: Icon(ProxyBridge.active
                ? Icons.verified_user_rounded
                : Icons.shield_outlined,
                color: ProxyBridge.active ? Colors.greenAccent : null),
            title: Text(tr('vpn.title')),
            subtitle: Text(ProxyBridge.active
                ? tr('vpn.on', [ProxyBridge.config.host])
                : tr('vpn.off')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const VpnScreen())),
          ),

          ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: Text(tr('reload.title')),
            subtitle: Text(tr('reload.hint')),
            onTap: () => reloadApp(context),
          ),

          // ------------------------------------------------- Langue
          section(tr('settings.general')),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(tr('settings.language')),
            subtitle: Text(label(langOptions, s.lang)),
            onTap: () async {
              final v = await pick(tr('settings.language'), langOptions, s.lang);
              if (v != null) s.update((x) => x.lang = v);
            },
          ),
          ListTile(
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: profileColor(app.profile),
              child: Text(
                app.profileName(app.profile).characters.firstOrNull?.toUpperCase() ?? '',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
            title: Text(tr('profile.title')),
            subtitle: Text(app.profileName(app.profile)),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilesScreen())),
          ),

          // ------------------------------------------------- Lecture
          section(tr('settings.playback')),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: Text(tr('settings.buffer')),
            subtitle: Text(label(bufferOptions, s.bufferMode)),
            onTap: () async {
              final v = await pick(tr('settings.buffer'), bufferOptions, s.bufferMode);
              if (v != null) s.update((x) => x.bufferMode = v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_rounded),
            title: Text(tr('settings.quality')),
            subtitle: Text(label(qualityOptions, s.quality)),
            onTap: () async {
              final v = await pick(tr('settings.quality'), qualityOptions, s.quality);
              if (v != null) s.update((x) => x.quality = v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.memory_rounded),
            title: Text(tr('settings.hwdec')),
            subtitle: Text(tr('settings.hwdecHint')),
            value: s.hwdec,
            onChanged: (v) => s.update((x) => x.hwdec = v),
          ),
          ListTile(
            leading: const Icon(Icons.aspect_ratio_rounded),
            title: Text(tr('fit.title')),
            subtitle: Text(fitLabel(s.videoFit)),
            onTap: () async {
              final v = await pick(tr('fit.title'),
                  [for (final f in VideoFit.values) (f, fitLabel(f))], s.videoFit);
              if (v != null) s.update((x) => x.videoFit = v);
            },
          ),
          if (Platform.isAndroid || Platform.isIOS)
            SwitchListTile(
              secondary: const Icon(Icons.picture_in_picture_alt_rounded),
              title: Text(tr('settings.autoPip')),
              subtitle: Text(tr(Platform.isIOS ? 'settings.autoPipIos' : 'settings.autoPipHint')),
              value: s.autoPip,
              onChanged: (v) => s.update((x) => x.autoPip = v),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.pause_circle_outline_rounded),
            title: Text(tr('settings.timeshift')),
            subtitle: Text(tr('settings.timeshiftHint', [s.timeshiftMinutes])),
            value: s.timeshift,
            onChanged: (v) => s.update((x) => x.timeshift = v),
          ),
          if (s.timeshift)
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(tr('settings.timeshiftLen')),
              subtitle: Text(tr('common.minutes', [s.timeshiftMinutes])),
              onTap: () async {
                final v = await pick<int>(tr('settings.timeshiftLen'), [
                  for (final m in [15, 30, 60, 90, 120])
                    (m, tr('common.minutes', [m])),
                ], s.timeshiftMinutes);
                if (v != null) s.update((x) => x.timeshiftMinutes = v);
              },
            ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(tr('settings.audioLang')),
            subtitle: Text(label(audioOptions, _codeOf(s.audioLangs))),
            onTap: () async {
              final v = await pick(tr('settings.audioLang'), audioOptions, _codeOf(s.audioLangs));
              if (v != null) s.update((x) => x.audioLangs = _mediaLangs[v] ?? '');
            },
          ),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: Text(tr('settings.subLang')),
            subtitle: Text(label(subOptions, _codeOf(s.subLangs))),
            onTap: () async {
              final v = await pick(tr('settings.subLang'), subOptions, _codeOf(s.subLangs));
              if (v != null) s.update((x) => x.subLangs = _mediaLangs[v] ?? '');
            },
          ),

          // ------------------------------------------ Guide et rappels
          section(tr('settings.guide')),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(tr('settings.remLead')),
            subtitle: Text(tr('common.minutes', [s.reminderLead])),
            onTap: () async {
              final v = await pick<int>(tr('settings.remLead'), [
                for (final m in [0, 1, 2, 5, 10, 15])
                  (m, tr('common.minutes', [m])),
              ], s.reminderLead);
              if (v != null) s.update((x) => x.reminderLead = v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.switch_video_rounded),
            title: Text(tr('settings.remAuto')),
            subtitle: Text(tr('settings.remAutoHint')),
            value: s.reminderAutoSwitch,
            onChanged: (v) => s.update((x) => x.reminderAutoSwitch = v),
          ),

          // ------------------------------------------ Enregistrements
          section(tr('tab.recordings')),
          FutureBuilder<Directory>(
            future: context.read<RecordingService>().folder(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(tr('rec.folder')),
              subtitle: Text(snap.data?.path ?? '...'),
              onTap: (Platform.isIOS)
                  ? null
                  : () async {
                      final dir = await FilePicker.getDirectoryPath(
                          dialogTitle: tr('rec.folder'));
                      if (dir != null) s.update((x) => x.recFolder = dir);
                    },
              trailing: s.recFolder.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('settings.resetFolder'),
                      icon: const Icon(Icons.restart_alt_rounded),
                      onPressed: () => s.update((x) => x.recFolder = ''),
                    ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('settings.margins')),
            subtitle: Text(tr('settings.marginsValue', [s.recPadBefore, s.recPadAfter])),
            onTap: () async {
              final before = await pick<int>(tr('settings.marginBefore'), [
                for (final m in [0, 1, 2, 5, 10]) (m, tr('common.minutes', [m])),
              ], s.recPadBefore);
              if (before == null || !context.mounted) return;
              final after = await pick<int>(tr('settings.marginAfter'), [
                for (final m in [0, 2, 3, 5, 10, 15, 30]) (m, tr('common.minutes', [m])),
              ], s.recPadAfter);
              if (after == null) return;
              s.update((x) {
                x.recPadBefore = before;
                x.recPadAfter = after;
              });
            },
          ),

          // ------------------------------------------ Controle parental
          section(tr('settings.parental')),
          ListTile(
            leading: Icon(app.parentalOn ? Icons.lock_rounded : Icons.lock_open_rounded),
            title: Text(app.parentalOn ? tr('pin.change') : tr('pin.set')),
            subtitle: Text(app.parentalOn ? tr('pin.on') : tr('pin.off')),
            onTap: () async {
              if (app.parentalOn && !await askPin(context)) return;
              if (!context.mounted) return;
              final pin = await chooseNewPin(context);
              if (pin != null) {
                s.update((x) => x.parentalPin = pin);
                app.lock();
              }
            },
          ),
          if (app.parentalOn) ...[
            SwitchListTile(
              secondary: const Icon(Icons.eighteen_up_rating_outlined),
              title: Text(tr('settings.lockAdult')),
              subtitle: Text(tr('settings.lockAdultHint')),
              value: s.lockAdult,
              onChanged: (v) async {
                if (!await askPin(context)) return;
                s.update((x) => x.lockAdult = v);
              },
            ),
            if (app.unlocked)
              ListTile(
                leading: const Icon(Icons.lock_clock_rounded),
                title: Text(tr('pin.lockNow')),
                onTap: app.lock,
              ),
            ListTile(
              leading: const Icon(Icons.no_encryption_gmailerrorred_rounded),
              title: Text(tr('pin.remove')),
              onTap: () async {
                if (!await askPin(context)) return;
                s.update((x) => x.parentalPin = '');
              },
            ),
          ],

          // ------------------------------------------ Categories
          section(tr('settings.categories')),
          ListTile(
            leading: const Icon(Icons.reorder_rounded),
            title: Text(tr('cat.title')),
            subtitle: Text(tr('cat.hint')),
            enabled: app.active != null,
            onTap: () async {
              if (app.parentalOn && !app.unlocked && !await askPin(context)) {
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CategoriesScreen()));
            },
          ),

          // ------------------------------------------ Sauvegarde
          section(tr('settings.backup')),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: Text(tr('backup.export')),
            subtitle: Text(tr('backup.exportHint')),
            onTap: () async {
              if (app.parentalOn && !await askPin(context)) return;
              try {
                final bytes = await Backup.export();
                final uri = await FilePicker.saveFile(
                  fileName: Backup.fileName(),
                  bytes: bytes,
                  mimeType: 'application/json',
                  dialogTitle: tr('backup.export'),
                );
                if (uri != null && context.mounted) {
                  toast(context, tr('backup.saved'));
                }
              } catch (e) {
                if (context.mounted) toast(context, '${tr('backup.error')} $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(tr('backup.import')),
            subtitle: Text(tr('backup.importHint')),
            onTap: () async {
              if (app.parentalOn && !await askPin(context)) return;
              final f = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: const ['json'],
                dialogTitle: tr('backup.import'),
              );
              if (f == null || !context.mounted) return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('backup.import')),
                  content: Text(tr('backup.confirm')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(tr('common.cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(tr('backup.restore'))),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              final settings = context.read<Settings>();
              final reminders = context.read<ReminderService>();
              final recorder = context.read<RecordingService>();
              try {
                await Backup.restore(await f.readAsBytes());
                await settings.reload();
                await reminders.reload();
                await recorder.reload();
                await app.reloadAll();
                if (context.mounted) toast(context, tr('backup.restored'));
              } catch (e) {
                if (context.mounted) toast(context, tr('backup.invalid'));
              }
            },
          ),

          // ------------------------------------------ A propos
          section(tr('settings.about')),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(tr('legal.title')),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(Brand.fullName),
            subtitle: Text(tr('settings.aboutText')),
          ),
        ],
      ),
    );
  }
}

/// Organisation des categories : ordre, masquage et verrouillage.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('cat.title')),
          bottom: TabBar(tabs: [
            Tab(text: tr('tab.live')),
            Tab(text: tr('tab.movies')),
            Tab(text: tr('tab.series')),
          ]),
        ),
        body: const TabBarView(children: [
          _CategoryList(type: ContentType.live),
          _CategoryList(type: ContentType.movie),
          _CategoryList(type: ContentType.series),
        ]),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final ContentType type;
  const _CategoryList({required this.type});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final groups = app.groupsFor(type, includeHidden: true);
    if (groups.isEmpty) return Center(child: Text(tr('common.noResults')));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('cat.help'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                onPressed: () => app.saveGroupPrefs(
                  order: {...app.groupOrder}..remove(type.index),
                  hidden: app.hiddenGroups
                      .where((k) => !k.startsWith('${type.index}|'))
                      .toSet(),
                ),
                child: Text(tr('cat.reset')),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: groups.length,
            onReorderItem: (from, to) {
              final list = [...groups];
              list.insert(to, list.removeAt(from));
              app.saveGroupPrefs(order: {...app.groupOrder, type.index: list});
            },
            itemBuilder: (context, i) {
              final g = groups[i];
              final key = AppState.groupKey(type, g);
              final hidden = app.hiddenGroups.contains(key);
              final locked = app.lockedGroups.contains(key);
              final autoLocked = !locked && app.isLockedGroup(type, g);
              return ListTile(
                key: ValueKey(key),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_indicator_rounded),
                ),
                title: Text(AppState.groupLabel(g),
                    style: TextStyle(
                        color: hidden
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                        decoration: hidden ? TextDecoration.lineThrough : null)),
                subtitle: autoLocked ? Text(tr('cat.autoLocked')) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: i > 0 ? tr('cat.up') : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: i == 0
                          ? null
                          : () {
                              final list = [...groups];
                              list.insert(i - 1, list.removeAt(i));
                              app.saveGroupPrefs(
                                  order: {...app.groupOrder, type.index: list});
                            },
                    ),
                    IconButton(
                      tooltip: hidden ? tr('cat.show') : tr('cat.hide'),
                      icon: Icon(hidden
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () {
                        final h = {...app.hiddenGroups};
                        hidden ? h.remove(key) : h.add(key);
                        app.saveGroupPrefs(hidden: h);
                      },
                    ),
                    IconButton(
                      tooltip: locked ? tr('cat.unlock') : tr('cat.lock'),
                      icon: Icon(
                        locked || autoLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: locked ? Colors.amber : null,
                      ),
                      onPressed: () async {
                        if (!app.parentalOn) {
                          final pin = await chooseNewPin(context);
                          if (pin == null || !context.mounted) return;
                          context.read<Settings>().update((x) => x.parentalPin = pin);
                        }
                        final l = {...app.lockedGroups};
                        locked ? l.remove(key) : l.add(key);
                        app.saveGroupPrefs(locked: l);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
