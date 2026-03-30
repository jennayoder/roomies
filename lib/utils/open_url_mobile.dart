import 'package:url_launcher/url_launcher.dart';

/// Opens a URL using url_launcher on mobile platforms.
Future<void> openUrl(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
