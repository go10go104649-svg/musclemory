/// App callbacks share one Auth project, but never share an OS URL scheme.
/// Keep these exact URLs (including the trailing slash) in the hosted allow list.
abstract final class AuthRedirects {
  static const setkeep = 'setkeep://login-callback/';
  static const trainer = 'setkeep-trainer://login-callback/';
  static const legacy = 'musclemory://login-callback/';
}
