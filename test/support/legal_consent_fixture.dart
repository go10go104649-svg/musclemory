import 'dart:convert';

import 'package:setkeep/main.dart';

String get acceptedLegalConsentJson => jsonEncode({
  'accepted': true,
  'over16': true,
  'acceptedAt': '2026-09-21T00:00:00.000Z',
  'termsVersion': LegalDocuments.termsVersion,
  'privacyVersion': LegalDocuments.privacyVersion,
});
