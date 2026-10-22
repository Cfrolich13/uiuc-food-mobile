import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/housing_balance_api.dart';
import '../data/housing_webview.dart';
import '../models/balance.dart';

/// Shows the University's own NetID sign-in page. Once the student lands on
/// University Housing's balances page, reads the balances and closes with
/// them.
///
/// The app never sees the password: it's typed into the University's page,
/// and none of this app's scripts run until the Housing page has loaded.
class HousingSignInScreen extends StatefulWidget {
  const HousingSignInScreen({super.key});

  @override
  State<HousingSignInScreen> createState() => _HousingSignInScreenState();
}

class _HousingSignInScreenState extends State<HousingSignInScreen> {
  late final WebViewController _controller;
  String _host = Uri.parse(HousingBalanceApi.balancesUrl).host;
  bool _loading = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: decideSignInNavigation,
        onUrlChange: (change) {
          final host = Uri.tryParse(change.url ?? '')?.host;
          if (host != null && host.isNotEmpty && mounted) setState(() => _host = host);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: _onPageFinished,
        onWebResourceError: (error) {
          if ((error.isForMainFrame ?? true) && mounted) {
            setState(() => _problem = "Couldn't reach the University. Check your connection.");
          }
        },
      ))
      ..loadRequest(Uri.parse(HousingBalanceApi.balancesUrl));
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted) return;
    setState(() => _loading = false);
    final uri = Uri.tryParse(url);
    if (uri == null || !HousingBalanceApi.isBalancesPage(uri)) return;
    final balance = HousingBalanceApi.parseBalancesPage(await readPageText(_controller));
    if (!mounted) return;
    if (balance == null) {
      setState(() => _problem = "Signed in, but this page didn't show meal plan balances.");
      return;
    }
    Navigator.of(context).pop<MealPlanBalance>(balance);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in with NetID'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shows which site is on screen, so it's clear this is the
                  // University's own page.
                  Row(children: [
                    Icon(Icons.lock_rounded, size: 16, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_host,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    _problem ??
                        'This is the University Housing website. Your password goes to the '
                            'University, not to this app, which only reads your balances.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: _problem == null ? muted : theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
