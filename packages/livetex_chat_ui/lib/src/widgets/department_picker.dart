import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";

import "../livetex_chat_theme.dart";
import "full_width_chat_button.dart";

/// Inline department picker shown in place of the composer when the server
/// sends `departmentRequest` with more than one option, mirroring native
/// Android `departmentsContainerView` from `a_chat.xml`. The 1-option case
/// is handled upstream (auto-select), so this widget always shows ≥2 items.
class DepartmentPicker extends StatelessWidget {
  const DepartmentPicker({
    super.key,
    required this.departments,
    required this.onSelect,
  });

  final List<DepartmentItem> departments;
  final void Function(DepartmentItem department) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                "Выберите куда направить ваше обращение",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: theme.systemText),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                // From native demo-lib `ECEDF1` — kept inline pending a
                // dedicated `departmentPickerBackground` theme token.
                color: const Color(0xFFECEDF1),
                borderRadius: BorderRadius.circular(theme.controlRadius),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in departments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FullWidthChatButton(
                        label: d.name,
                        background: theme.departmentButton,
                        foreground: theme.departmentButtonText,
                        onPressed: () => onSelect(d),
                      ),
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
