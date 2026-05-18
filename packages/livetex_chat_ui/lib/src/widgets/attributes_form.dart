import "package:flutter/material.dart";

import "../livetex_chat_theme.dart";

/// Inline attributes form rendered in place of the composer, mirroring native
/// Android `attributesContainerView` from `a_chat.xml`. Three optional fields
/// (Имя / Телефон / E-mail) and a full-width green Отправить button. Empty
/// fields are accepted — backend asks but does not require an answer.
class AttributesForm extends StatefulWidget {
  const AttributesForm({super.key, required this.onSubmit});

  final void Function({String? name, String? phone, String? email}) onSubmit;

  @override
  State<AttributesForm> createState() => _AttributesFormState();
}

class _AttributesFormState extends State<AttributesForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _trimOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  void _submit() {
    widget.onSubmit(
      name: _trimOrNull(_name.text),
      phone: _trimOrNull(_phone.text),
      email: _trimOrNull(_email.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(60, 10, 60, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.white,
              elevation: 10,
              shadowColor: Colors.black26,
              // Material 3 tints elevated surfaces with the seed color,
              // which on a white card-on-white-background washes the
              // drop shadow out. Disable the tint so the shadow stays
              // visible — mirrors Android's cardElevation behavior.
              surfaceTintColor: Colors.transparent,
              borderRadius: BorderRadius.circular(theme.cardRadius),
              child: DecoratedBox(
                // Flutter elevation drops shadow downward only — the top
                // edge of a white card on a white Scaffold has nothing to
                // separate it from the background. A 1px hairline border
                // (same #E5E5E5 used between fields and on the composer)
                // gives the card a visible outline on all four sides.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(theme.cardRadius),
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AttrField(controller: _name, hint: "Имя"),
                    const Divider(height: 1, color: Color(0xFFE5E5E5)),
                    _AttrField(
                      controller: _phone,
                      hint: "Телефон",
                      keyboardType: TextInputType.phone,
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E5E5)),
                    _AttrField(
                      controller: _email,
                      hint: "E-mail",
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.attributesAccent,
                  foregroundColor: theme.attributesAccentText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.cardRadius),
                  ),
                ),
                onPressed: _submit,
                child: const Text(
                  "Отправить",
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttrField extends StatelessWidget {
  const _AttrField({
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: 100,
      maxLines: 1,
      style: TextStyle(fontSize: 16, color: theme.composerText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: theme.attributesHint),
        counterText: "",
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 24,
        ),
        border: InputBorder.none,
      ),
    );
  }
}
