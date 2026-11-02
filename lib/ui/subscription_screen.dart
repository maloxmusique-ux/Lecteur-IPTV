import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../l10n/i18n.dart';
import '../services/license.dart';
import '../services/store_billing.dart';

/// Verifie que l'appareil peut lire. Sinon, ouvre l'ecran des forfaits.
/// Renvoie vrai si la lecture est permise (eventuellement apres paiement).
Future<bool> ensureLicensed(BuildContext context) async {
  final lic = context.read<LicenseService>();
  if (lic.canPlay) return true;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
  return lic.canPlay;
}

String _date(DateTime d) => '${d.day} ${monthShort(d.month)} ${d.year}';

DateTime _nextCharge(Plan p, [DateTime? from]) {
  final n = from ?? DateTime.now();
  return DateTime(n.year, n.month + p.months, n.day);
}

String planName(Plan p) => tr('plan.${p.name}');

/// Prix a afficher : celui de la boutique (devise du pays) si disponible.
String planPrice(BuildContext context, Plan p) =>
    context.read<LicenseService>().store?.priceOf(p) ?? p.price;

/// Liens obligatoires : conditions d'utilisation et confidentialite.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          onPressed: () => launchUrl(Uri.parse(Brand.termsUrl),
              mode: LaunchMode.externalApplication),
          child: Text(tr('legal.terms'), style: style),
        ),
        TextButton(
          onPressed: () => launchUrl(Uri.parse(Brand.privacyUrl),
              mode: LaunchMode.externalApplication),
          child: Text(tr('legal.privacy'), style: style),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- Forfaits

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Plan _selected = Plan.yearly;
  bool _busy = false;

  Future<void> _pay() async {
    final lic = context.read<LicenseService>();
    setState(() => _busy = true);
    try {
      final ok = await startPayment(context, _selected);
      if (ok && mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent, size: 48),
            title: Text(tr('pay.thanks')),
            content: Text(tr('pay.activated', [planName(_selected)])),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(c), child: Text(tr('common.ok'))),
            ],
          ),
        );
        if (mounted && lic.canPlay) Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('pay.error'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final theme = Theme.of(context);
    final info = lic.info;
    final expired = info.status == LicenseStatus.expired;
    final wide = MediaQuery.sizeOf(context).width > 760;

    final cards = [
      for (final p in Plan.values)
        _PlanCard(
          plan: p,
          selected: _selected == p,
          onTap: () => setState(() => _selected = p),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('pay.title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  expired
                      ? (info.plan == null
                          ? tr('pay.trialOver')
                          : tr('pay.subOver'))
                      : (info.status == LicenseStatus.trial
                          ? tr('pay.trialLeft', [info.trialDaysLeft])
                          : tr('pay.choose')),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(tr('pay.what'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 18),
                if (wide)
                  LayoutBuilder(builder: (context, box) {
                    final w = (box.maxWidth - 12 * (cards.length - 1)) / cards.length;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, c) in cards.indexed) ...[
                          if (i > 0) const SizedBox(width: 12),
                          SizedBox(width: w, height: 170, child: c),
                        ],
                      ],
                    );
                  })
                else
                  ...[
                    for (final c in cards)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10), child: c),
                  ],
                const SizedBox(height: 18),
                _Terms(plan: _selected),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    autofocus: true,
                    onPressed: _busy ? null : _pay,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.lock_rounded),
                    label: Text(
                      lic.store != null && _selected.recurring
                          ? tr('pay.startTrial')
                          : tr('pay.payNow', [planPrice(context, _selected)]),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(tr('pay.secure'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (lic.store != null)
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await lic.store!.restore();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? tr('pay.restored') : tr('pay.nothingToRestore'))));
                          if (ok) Navigator.of(context).maybePop();
                        },
                        icon: const Icon(Icons.restore_rounded),
                        label: Text(tr('pay.restore')),
                      )
                    else ...[
                      TextButton.icon(
                        onPressed: () async {
                          await lic.refresh();
                          if (context.mounted && lic.canPlay) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr('pay.alreadyPaid')),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await showRedeemDialog(context);
                          if (ok && context.mounted) Navigator.of(context).maybePop();
                        },
                        icon: const Icon(Icons.card_giftcard_rounded),
                        label: Text(tr('code.have')),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HelpScreen())),
                      icon: const Icon(Icons.help_outline_rounded),
                      label: Text(tr('help.title')),
                    ),
                  ],
                ),
                const LegalLinks(),
                if (lic.store == null) ...[
                  const SizedBox(height: 8),
                  Center(child: _MacChip(mac: lic.mac)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = plan == Plan.yearly;
    final saving = plan.recurring && plan.months > 1
        ? (100 - plan.monthlyEquivalent / Plan.monthly.monthlyEquivalent * 100).round()
        : 0;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (best)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.amber, borderRadius: BorderRadius.circular(6)),
                  child: Text(tr('plan.best'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              Text(planName(plan),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(planPrice(context, plan),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                plan.recurring
                    ? (plan.months == 1
                        ? tr('plan.perMonth')
                        : tr('plan.perMonths', [
                            plan.months,
                            plan.monthlyEquivalent
                                .toStringAsFixed(2)
                                .replaceAll('.', ','),
                          ]))
                    : tr('plan.once'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (saving > 0) ...[
                const SizedBox(height: 4),
                Text(tr('plan.save', [saving]),
                    style: const TextStyle(
                        color: Colors.greenAccent, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Conditions bien visibles sous les forfaits.
class _Terms extends StatelessWidget {
  final Plan plan;
  const _Terms({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: color ?? Colors.greenAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: color == null ? FontWeight.w600 : null)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: context.read<LicenseService>().store != null
            ? [
                if (plan.recurring) ...[
                  line(Icons.card_giftcard_rounded, tr('terms.storeTrial')),
                  line(Icons.autorenew_rounded,
                      tr('terms.storeRenews', [
                        planName(plan).toLowerCase(),
                        planPrice(context, plan),
                        StoreBilling.storeName,
                      ]),
                      color: theme.colorScheme.onSurfaceVariant),
                  line(Icons.check_circle_rounded,
                      tr('terms.storeCancel', [StoreBilling.storeName])),
                ] else ...[
                  line(Icons.check_circle_rounded, tr('terms.once')),
                  line(Icons.check_circle_rounded, tr('terms.noRenew')),
                ],
                line(Icons.devices_rounded,
                    tr('terms.storeDevices', [StoreBilling.storeName]),
                    color: theme.colorScheme.onSurfaceVariant),
              ]
            : plan.recurring
            ? [
                line(Icons.check_circle_rounded, tr('terms.noCommitment')),
                line(Icons.check_circle_rounded, tr('terms.cancelAnytime')),
                line(Icons.autorenew_rounded,
                    tr('terms.renews', [
                      planName(plan).toLowerCase(),
                      plan.price,
                      _date(_nextCharge(plan)),
                    ]),
                    color: theme.colorScheme.onSurfaceVariant),
                line(Icons.devices_rounded, tr('terms.oneDevice'),
                    color: theme.colorScheme.onSurfaceVariant),
              ]
            : [
                line(Icons.check_circle_rounded, tr('terms.once')),
                line(Icons.check_circle_rounded, tr('terms.noRenew')),
                line(Icons.devices_rounded, tr('terms.oneDevice'),
                    color: theme.colorScheme.onSurfaceVariant),
              ],
      ),
    );
  }
}

class _MacChip extends StatelessWidget {
  final String mac;
  const _MacChip({required this.mac});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.memory_rounded, size: 18),
      label: Text('${tr('sub.mac')} : $mac',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
      tooltip: tr('sub.copy'),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: mac));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('sub.copied'))));
      },
    );
  }
}

// ----------------------------------------------------------- Paiement

/// Ouvre la page de paiement et attend la confirmation.
Future<bool> startPayment(BuildContext context, Plan plan) async {
  final lic = context.read<LicenseService>();
  // Versions boutiques : fenetre de paiement d'Apple ou de Google.
  if (lic.store != null) return lic.store!.buy(plan);
  if (Brand.testMode) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('pay.testTitle')),
        content: Text(tr('pay.testText', [planName(plan), plan.price])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('pay.testPay'))),
        ],
      ),
    );
    if (ok != true) return false;
    await lic.testPay(plan);
    return true;
  }

  final session = await lic.checkout(plan);
  final uri = Uri.parse(session.url);
  final mobile = Platform.isAndroid || Platform.isIOS;
  // Mobile : la page de paiement s'ouvre DANS l'app (navigateur integre).
  final opened = await launchUrl(uri,
      mode: mobile ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WaitPayment(url: session.url, opened: opened),
      ) ??
      false;
}

/// Attente du paiement, avec code QR pour payer depuis un telephone.
class _WaitPayment extends StatefulWidget {
  final String url;
  final bool opened;
  const _WaitPayment({required this.url, required this.opened});

  @override
  State<_WaitPayment> createState() => _WaitPaymentState();
}

class _WaitPaymentState extends State<_WaitPayment> {
  @override
  void initState() {
    super.initState();
    context.read<LicenseService>().waitForActivation().then((ok) {
      if (mounted) Navigator.pop(context, ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(tr('pay.waiting')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.opened ? tr('pay.opened') : tr('pay.scan'),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(data: widget.url, size: 200),
            ),
            const SizedBox(height: 10),
            Text(tr('pay.qrHint'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('common.cancel')),
        ),
      ],
    );
  }
}

// ----------------------------------------------------- Mon abonnement

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  Future<void> _confirmCancel(BuildContext context, LicenseInfo info) async {
    final until = info.expiresAt == null ? '' : _date(info.expiresAt!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined, size: 40, color: Colors.redAccent),
        title: Text(tr('sub.cancelQ')),
        content: Text(tr('sub.cancelText', [until])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('sub.keep'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('sub.confirmCancel')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final lic = context.read<LicenseService>();
    try {
      await lic.cancel();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('sub.cancelled', [until])),
            duration: const Duration(seconds: 6)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('pay.error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final info = lic.info;
    final theme = Theme.of(context);
    final store = info.source == 'apple' || info.source == 'google';
    final storeBuild = lic.store != null;
    final gift = info.source == 'gift';
    // Un acces offert ne se renouvelle jamais : rien a annuler.
    final recurring = !gift && (info.plan?.recurring ?? false);
    final active = info.status == LicenseStatus.active;

    final (statusText, statusColor) = switch (info.status) {
      LicenseStatus.trial =>
        (tr('sub.trial', [info.trialDaysLeft]), Colors.lightBlueAccent),
      LicenseStatus.active => (tr('sub.active'), Colors.greenAccent),
      LicenseStatus.expired => (tr('sub.expired'), Colors.redAccent),
    };

    String detail;
    if (info.status == LicenseStatus.trial) {
      detail = tr('sub.trialEnds', [_date(info.trialEndsAt)]);
    } else if (active && gift && info.expiresAt == null) {
      detail = tr('code.giftLifetime');
    } else if (active && gift) {
      detail = tr('code.giftUntil', [_date(info.expiresAt!)]);
    } else if (active && info.plan == Plan.lifetime) {
      detail = tr('sub.lifetime');
    } else if (active && store) {
      detail = info.plan == Plan.lifetime
          ? tr('sub.lifetime')
          : tr('sub.storeManaged', [StoreBilling.storeName]);
    } else if (active && info.autoRenew && info.expiresAt != null) {
      detail = tr('sub.nextCharge', [info.plan!.price, _date(info.expiresAt!)]);
    } else if (active && info.expiresAt != null) {
      detail = tr('sub.endsOn', [_date(info.expiresAt!)]);
    } else {
      detail = tr('sub.noAccess');
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('sub.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(statusText,
                            style: TextStyle(
                                color: statusColor, fontWeight: FontWeight.w800)),
                      ),
                      const Spacer(),
                      if (lic.loading)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (store && active && info.plan != null)
                    Text('${planName(info.plan!)} · ${planPrice(context, info.plan!)}',
                        style: theme.textTheme.titleLarge)
                  else if (gift && active)
                    Row(children: [
                      const Icon(Icons.card_giftcard_rounded, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(tr('code.giftAccess'), style: theme.textTheme.titleLarge),
                    ])
                  else if (info.plan != null)
                    Text('${planName(info.plan!)} · ${info.plan!.price}',
                        style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(detail, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 14),
                  if (!storeBuild || gift) _MacChip(mac: lic.mac),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Annulation : visible, en clair, en un clic.
          if (active && recurring && info.autoRenew && !store) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('sub.cancelInfo'), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white),
                      onPressed:
                          lic.loading ? null : () => _confirmCancel(context, info),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(tr('sub.cancel'),
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (active && recurring && !info.autoRenew && !store) ...[
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: lic.loading ? null : lic.resume,
                icon: const Icon(Icons.autorenew_rounded),
                label: Text(tr('sub.resume')),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Abonnement de la boutique : annulation visible, en un toucher.
          if (store && recurring) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('sub.storeCancelInfo', [StoreBilling.storeName]),
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white),
                      onPressed: StoreBilling.manage,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(tr('sub.storeManage'),
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!active || info.plan != Plan.lifetime)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaywallScreen())),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: Text(active ? tr('sub.change') : tr('sub.subscribe')),
            ),

          if (storeBuild)
            TextButton.icon(
              onPressed: () async {
                final ok = await lic.store!.restore();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? tr('pay.restored') : tr('pay.nothingToRestore'))));
              },
              icon: const Icon(Icons.restore_rounded),
              label: Text(tr('pay.restore')),
            ),
          if (!storeBuild && (!active || info.expiresAt != null)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showRedeemDialog(context),
              icon: const Icon(Icons.card_giftcard_rounded),
              label: Text(tr('code.have')),
            ),
          ],
          if (info.payments.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(tr('sub.receipts'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final p in info.payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_rounded),
                title: Text(
                    '${p.plan == null ? '' : planName(p.plan!)} · ${(p.amountCents / 100).toStringAsFixed(2).replaceAll('.', ',')} \$'),
                subtitle: Text(_date(p.date)),
                trailing: p.receiptUrl.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('sub.receipt'),
                        icon: const Icon(Icons.open_in_new_rounded),
                        onPressed: () => launchUrl(Uri.parse(p.receiptUrl),
                            mode: LaunchMode.externalApplication),
                      ),
              ),
          ],
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(tr('help.title')),
            subtitle: Text(tr('help.subtitle')),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
          const LegalLinks(),
          if (Brand.testMode && !storeBuild) ...[
            const Divider(height: 32),
            Text(tr('sub.testTools'), style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                    onPressed: () => lic.testReset(),
                    child: Text(tr('sub.testRestart'))),
                OutlinedButton(
                    onPressed: () => lic.testReset(expired: true),
                    child: Text(tr('sub.testEnd'))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bandeau discret pendant l'essai, plus visible quand il est termine.
class TrialBanner extends StatelessWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<LicenseService>().info;
    if (info.status == LicenseStatus.active) return const SizedBox.shrink();
    final expired = info.status == LicenseStatus.expired;
    final color = expired ? Colors.redAccent : Theme.of(context).colorScheme.primary;
    return Material(
      color: color.withValues(alpha: 0.15),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(expired ? Icons.lock_rounded : Icons.hourglass_bottom_rounded,
                  size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  expired
                      ? tr('banner.expired')
                      : tr('banner.trial', [info.trialDaysLeft]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(tr('sub.subscribe'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Aide

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lic = context.read<LicenseService>();
    final theme = Theme.of(context);
    final faq = [
      // Versions boutiques : pas de codes, pas d'adresse MAC, annulation
      // dans le compte Apple / Google.
      for (final k in Brand.storeBilling
          ? const ['1', '2', '3', '4s', '5s', '6s', '9']
          : const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        (tr('faq.q$k', [StoreBilling.storeName]), tr('faq.a$k', [StoreBilling.storeName])),
    ];
    Future<void> write() async {
      final body = tr('help.mailBody', [
        lic.mac,
        Platform.operatingSystem,
        lic.info.status.name,
      ]);
      final uri = Uri(
        scheme: 'mailto',
        path: Brand.supportEmail,
        query: 'subject=${Uri.encodeComponent('${Brand.name} : ${tr('help.mailSubject')}')}'
            '&body=${Uri.encodeComponent(body)}',
      );
      if (!await launchUrl(uri) && context.mounted) {
        Clipboard.setData(const ClipboardData(text: Brand.supportEmail));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('help.copied', [Brand.supportEmail]))));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('help.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(tr('help.faq'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final (q, a) in faq)
            Card(
              child: ExpansionTile(
                shape: const Border(),
                title: Text(q),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(a)],
              ),
            ),
          const SizedBox(height: 24),
          Text(tr('help.contact'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(tr('help.contactText')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: write,
            icon: const Icon(Icons.mail_outline_rounded),
            label: Text(tr('help.write')),
          ),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(Brand.supportEmail,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          const SizedBox(height: 8),
          Center(child: _MacChip(mac: lic.mac)),
        ],
      ),
    );
  }
}

/// Fenetre "J'ai un code" : renvoie true si le code a debloque l'app.
Future<bool> showRedeemDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
      context: context, builder: (_) => const _RedeemDialog());
  return ok ?? false;
}

class _RedeemDialog extends StatefulWidget {
  const _RedeemDialog();
  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final lic = context.read<LicenseService>();
    final err = await lic.redeem(code);
    if (!mounted) return;
    if (err == null) {
      final info = lic.info;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(
            info.expiresAt == null
                ? tr('code.okLifetime')
                : tr('code.okUntil', [_date(info.expiresAt!)]),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ));
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = tr(err);
      });
      _focus.requestFocus();
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.card_giftcard_rounded, size: 40, color: Colors.amber),
      title: Text(tr('code.title')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('code.text')),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'CANALIX-XXXX-XXXX',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (Brand.testMode) ...[
              const SizedBox(height: 8),
              Text(tr('code.testHint'),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(tr('common.cancel'))),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('code.use')),
        ),
      ],
    );
  }
}
