/// Drop-in chat UI for the LiveTex Visitor-API plugin.
///
/// `LivetexChatScreen` is the one-line integration; `LivetexChatTheme`
/// covers brand customization; the rest of the exports are the building
/// blocks the screen is composed of, available for host apps that want
/// to assemble their own layout. See `docs/INTEGRATION.md` for details.
library livetex_chat_ui;

export "src/livetex_chat_screen.dart";
export "src/livetex_chat_theme.dart";
export "src/widgets/attributes_form.dart";
export "src/widgets/bot_keyboard.dart";
export "src/widgets/composer.dart";
export "src/widgets/connection_banner.dart";
export "src/widgets/department_picker.dart";
export "src/widgets/full_width_chat_button.dart";
export "src/widgets/message_tile.dart";
export "src/widgets/rating_widget.dart";
