import 'package:url_launcher/url_launcher.dart' as launcher_pkg;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

abstract class MapLauncher {
  Future<bool> canLaunchUrl(Uri url);
  Future<bool> launchUrl(Uri url, {LaunchMode mode});
}

class DefaultMapLauncher implements MapLauncher {
  const DefaultMapLauncher();

  @override
  Future<bool> canLaunchUrl(Uri url) => launcher_pkg.canLaunchUrl(url);

  @override
  Future<bool> launchUrl(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) =>
      launcher_pkg.launchUrl(url, mode: mode);
}

Future<void> openInMaps(
  double lat,
  double lon, {
  String? label,
  MapLauncher launcher = const DefaultMapLauncher(),
}) async {
  final encodedLabel = Uri.encodeComponent(label ?? "Location");

  final googleUrl = Uri.parse("geo:$lat,$lon?q=$lat,$lon($encodedLabel)");
  final appleUrl = Uri.parse(
    "http://maps.apple.com/?ll=$lat,$lon&q=$encodedLabel",
  );
  final webUrl = Uri.parse(
    "https://www.google.com/maps/search/?api=1&query=$lat,$lon",
  );

  if (await launcher.canLaunchUrl(googleUrl)) {
    await launcher.launchUrl(googleUrl);
    return;
  }

  if (await launcher.canLaunchUrl(appleUrl)) {
    await launcher.launchUrl(appleUrl);
    return;
  }

  if (await launcher.canLaunchUrl(webUrl)) {
    await launcher.launchUrl(webUrl, mode: LaunchMode.externalApplication);
    return;
  }

  throw Exception("No maps app or browser available to open location.");
}
