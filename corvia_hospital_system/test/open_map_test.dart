import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mycorvia/open_map.dart';

class MockMapLauncher extends Mock implements MapLauncher {}

void main() {
  setUpAll(() {
    // Register fallback values for both custom non-nullable types Mocktail will encounter
    registerFallbackValue(Uri.parse('https://maps.google.com'));
    registerFallbackValue(LaunchMode.platformDefault);
  });

  group('openInMaps fallback tests', () {
    late MockMapLauncher mockLauncher;

    setUp(() {
      mockLauncher = MockMapLauncher();
    });

    test('falls back to browser when no map apps available', () async {
      final lat = -25.746;
      final lon = 28.188;

      // Handle all incoming Uri verification calls dynamically
      when(() => mockLauncher.canLaunchUrl(any())).thenAnswer((
        invocation,
      ) async {
        final requestedUri = invocation.positionalArguments.first as Uri;

        // The Apple HTTP URL may open the native Maps app, so keep it
        // unavailable here and allow only the actual Google web fallback.
        return requestedUri.scheme == 'https' &&
            requestedUri.host == 'www.google.com';
      });

      // FIX: Correct Mocktail named argument syntax -> any(named: 'mode')
      when(
        () => mockLauncher.launchUrl(any(), mode: any(named: 'mode')),
      ).thenAnswer((_) async => true);

      // Act
      await openInMaps(lat, lon, launcher: mockLauncher);

      // Assert
      verify(
        () => mockLauncher.launchUrl(
          any(that: predicate<Uri>((uri) => uri.scheme.startsWith('http'))),
          mode: LaunchMode.externalApplication,
        ),
      ).called(1);
    });

    test('throws error when no apps or browser available', () async {
      final lat = -25.746;
      final lon = 28.188;

      when(
        () => mockLauncher.canLaunchUrl(any()),
      ).thenAnswer((_) async => false);

      expect(
        () async => await openInMaps(lat, lon, launcher: mockLauncher),
        throwsException,
      );
    });
  });
}
