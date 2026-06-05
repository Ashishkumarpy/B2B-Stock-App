const String connectionWarningTitle = 'Connection unavailable';
const String connectionWarningMessage =
    'Cannot reach the server right now. Check your internet connection or server address, then try again.';

String userFriendlyErrorMessage(Object error) {
  final raw = error.toString();
  final text = raw.toLowerCase();
  if (text == connectionWarningMessage.toLowerCase()) {
    return connectionWarningMessage;
  }
  if (text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('network error') ||
      text.contains('failed host lookup') ||``
      text.contains('connection refused') ||
      text.contains('connection timed out') ||
      text.contains('supabase') ||
      text.contains('anonkey') ||
      text.contains('api key')) {
    return connectionWarningMessage;
  }

  return 'Something went wrong. Please try again.';
}
