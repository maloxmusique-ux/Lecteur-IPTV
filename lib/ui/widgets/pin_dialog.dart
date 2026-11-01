import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/i18n.dart';
import '../../state/app_state.dart';

/// Demande le code parental. Renvoie vrai si le code est correct
/// (ou si le controle parental est desactive).
Future<bool> askPin(BuildContext context, {String? title}) async {
  final app = context.read<AppState>();
  if (!app.parentalOn) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(
      title: title ?? tr('pin.enter'),
      check: app.checkPin,
    ),
  );
  return ok == true;
}

/// Deverrouille le contenu protege pour la session.
Future<bool> askUnlock(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.profile.kids) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(tr('pin.kidsBlocked'))));
    return false;
  }
  final ok = await askPin(context, title: tr('pin.unlockTitle'));
  if (ok) app.unlock();
  return ok;
}

/// Choisit un nouveau code a 4 chiffres. Renvoie le code ou null.
Future<String?> chooseNewPin(BuildContext context) async {
  final first = await showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: tr('pin.new')),
  );
  if (first == null || !context.mounted) return null;
  final second = await showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: tr('pin.confirm')),
  );
  if (second == null) return null;
  if (second != first) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr('pin.mismatch'))));
    }
    return null;
  }
  return first;
}

class _PinDialog extends StatefulWidget {
  final String title;

  /// Si fourni, le dialogue renvoie vrai/faux ; sinon il renvoie le code.
  final bool Function(String)? check;
  const _PinDialog({required this.title, this.check});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _c = TextEditingController();
  String? _error;

  void _submit() {
    final v = _c.text;
    if (v.length != 4) {
      setState(() => _error = tr('pin.fourDigits'));
      return;
    }
    final check = widget.check;
    if (check == null) {
      Navigator.pop(context, v);
    } else if (check(v)) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = tr('pin.wrong');
        _c.clear();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 260,
        child: TextField(
          controller: _c,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 16),
          decoration: InputDecoration(errorText: _error, counterText: ''),
          onChanged: (v) {
            if (v.length == 4) _submit();
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(tr('common.ok'))),
      ],
    );
  }
}
