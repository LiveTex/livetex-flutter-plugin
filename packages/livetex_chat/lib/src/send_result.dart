/// Результат команды, отправленной на сервер и ожидающей `result`-фрейм.
sealed class SendResult {
  const SendResult();
}

/// Сервер подтвердил команду без ошибок.
class SendSuccess extends SendResult {
  const SendSuccess();
}

/// Сервер вернул ошибку для команды.
class SendError extends SendResult {
  const SendError(this.code);

  /// Код(ы) ошибки из `result.error`, объединённые через запятую.
  final String code;
}

/// `result`-фрейм не пришёл за отведённое время.
class SendTimeout extends SendResult {
  const SendTimeout();
}

/// Команду не удалось отправить — нет активной сессии.
class SendNotConnected extends SendResult {
  const SendNotConnected();
}
