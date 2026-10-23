import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/housing_balance_api.dart';
import '../data/housing_webview.dart';
import '../data/session_cookies.dart';
import '../data/sign_in_log.dart';
import '../models/balance.dart';
import '../state/controllers.dart';

/// Opens the sign-in screen and shows the balances it reads.
Future<void> signInToHousing(BuildContext context) async {
  final controller = context.read<BalanceController>();
  final balance = await Navigator.of(context)
      .push<MealPlanBalance>(MaterialPageRoute(builder: (_) => const HousingSignInScreen()));
  if (balance != null) await controller.acceptSignIn(balance);
}

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
  SignInRecorder? _record;

  @override
  void initState() {
    super.initState();
    _record = context.read<SignInLog?>()?.start('Sign-in screen');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final decision = decideSignInNavigation(request);
            if (request.isMainFrame) {
              _record?.navigation(request.url,
                  allowed: decision == NavigationDecision.navigate);
            }
            return decision;
          },
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
        ),
      );
    // With the earlier sign-in restored, Microsoft can recognize the session
    // instead of asking for the password again.
    SessionCookies.restore().then((restored) {
      if (restored > 0) _record?.note('restored $restored saved sign-in cookies');
      if (mounted) _controller.loadRequest(Uri.parse(HousingBalanceApi.balancesUrl));
    });
  }

  @override
  void dispose() {
    _record?.finish('closed before reaching the balances page');
    super.dispose();
  }

  Future<void> _onPageFinished(String url) async {
    _record?.pageLoaded(url);
    if (!mounted) return;
    setState(() => _loading = false);
    final uri = Uri.tryParse(url);
    if (uri == null || !HousingBalanceApi.isBalancesPage(uri)) return;
    final balance = HousingBalanceApi.parseBalancesPage(await readPageText(_controller));
    if (!mounted) return;
    if (balance == null) {
      _record?.note("balances page didn't show balances");
      setState(() => _problem = "Signed in, but this page didn't show meal plan balances.");
      return;
    }
    _record?.finish('signed in and read the balances');
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
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
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
                    Row(
                      children: [
                        Icon(Icons.lock_rounded, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _host,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _problem ??
                          'This is the University Housing website. Your password goes to the '
                              'University, not to this app, which only reads your balances. '
                              'If Microsoft lists your account, tap it to continue.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _problem == null ? muted : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
