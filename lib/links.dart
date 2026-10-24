import 'package:flutter/services.dart';

/// Public page where users can sponsor the project (GitHub Sponsors).
const kSponsorUrl = 'https://github.com/sponsors/karem505';

const _channel = MethodChannel('hermes/background');

/// Opens [url] in the user's browser via an Android ACTION_VIEW intent.
/// Returns false when no handler exists (tests, non-Android platforms).
Future<bool> openExternalUrl(String url) async {
  try {
    await _channel.invokeMethod<void>('openUrl', {'url': url});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
