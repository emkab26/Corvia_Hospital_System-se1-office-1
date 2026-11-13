import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// A website link is independent of the authenticated checkout/ITN workflow.
class PaymentWebsiteCard extends StatefulWidget {
  const PaymentWebsiteCard({super.key});
  static Uri? website({String? configured, required bool debug}) {
    final value = configured?.trim();
    final url = Uri.tryParse(value == null || value.isEmpty
        ? (debug ? 'http://127.0.0.1:8080' : '')
        : value);
    if (url == null ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (url.path.isNotEmpty && url.path != '/')) {
      return null;
    }
    final local = ['localhost', '127.0.0.1', '::1'].contains(url.host);
    if (url.scheme != 'https' && !(debug && local && url.scheme == 'http')) {
      return null;
    }
    return url;
  }

  @override
  State<PaymentWebsiteCard> createState() => _PaymentWebsiteCardState();
}

class _PaymentWebsiteCardState extends State<PaymentWebsiteCard> {
  late final Uri? url;
  String state = 'Connection not checked';
  bool checking = false;
  @override
  void initState() {
    super.initState();
    url = PaymentWebsiteCard.website(
        configured: dotenv.isInitialized
            ? dotenv.maybeGet('PAYMENT_WEBSITE_URL')
            : null,
        debug: kDebugMode);
  }

  Future<void> check() async {
    setState(() => checking = true);
    try {
      final response = await http
          .get(url!.resolve('/healthz'))
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          body is! Map ||
          body['app'] != 'corvia-payment-portal') {
        throw StateError('Unavailable');
      }
      if (mounted) {
        setState(() => state = body['mode'] == 'preview'
            ? 'Website reachable • preview only, checkout disabled'
            : 'Website reachable • ${body['mode']} configuration; payment confirmation still requires PayFast');
      }
    } catch (_) {
      if (mounted) {
        setState(() => state =
            'Website could not be reached. Start the local payment portal, or check its configured address.');
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local =
        url != null && ['localhost', '127.0.0.1', '::1'].contains(url!.host);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Payment website',
                  style: Theme.of(context).textTheme.titleLarge),
              if (url == null)
                const Text(
                    'A public payment website address has not been configured.')
              else ...[
                SelectableText(url.toString()),
                Text(local
                    ? 'Local on this computer • not publicly hosted'
                    : 'Configured HTTPS website'),
                Text(state),
                if (local)
                  const Text(
                      'On a phone, localhost refers to the phone. Open this preview on the computer running Corvia.'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.icon(
                      onPressed: () async {
                        final opened = await launchUrl(url!,
                            mode: LaunchMode.externalApplication);
                        if (!opened && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Could not open the website.')));
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open payment website')),
                  OutlinedButton(
                      onPressed: checking ? null : check,
                      child: Text(checking ? 'Checking…' : 'Check connection'))
                ])
              ]
            ])));
  }
}
