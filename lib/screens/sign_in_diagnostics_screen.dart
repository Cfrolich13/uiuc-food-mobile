import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/session_cookies.dart';
import '../data/sign_in_log.dart';
import '../widgets/common.dart';

/// Shows what happened during recent University sign-ins and background
/// balance refreshes, and which sign-in cookies the app's WebView holds, so
/// problems staying signed in can be traced. Can be copied as a text report.
class SignInDiagnosticsScreen extends StatefulWidget {
  const SignInDiagnosticsScreen({super.key, required this.log});

  final SignInLog log;

  @override
  State<SignInDiagnosticsScreen> createState() => _SignInDiagnosticsScreenState();
}

class _SignInDiagnosticsScreenState extends State<SignInDiagnosticsScreen> {
  late Future<SignInCookieReport?> _cookies = SessionCookies.describe();

  static final _time = DateFormat('MMM d, h:mm:ss a');

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final report = widget.log.report(current: await _cookies);
    await Clipboard.setData(ClipboardData(text: report));
    messenger.showSnackBar(const SnackBar(content: Text('Copied the diagnostics report')));
  }

  Future<void> _clear() async {
    await widget.log.clear();
    setState(() {
      _cookies = SessionCookies.describe();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Sign-in diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _clear,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final cookies = SessionCookies.describe();
          setState(() {
            _cookies = cookies;
          });
          await cookies;
        },
        child: ListenableBuilder(
          listenable: widget.log,
          builder: (context, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Each balance refresh and sign-in is recorded here: the University pages it '
                'went through and the sign-in cookies afterwards. Only addresses and cookie '
                'names are kept, never passwords, cookie contents or balances, and only on '
                'this device.',
                style: muted,
              ),
              const SizedBox(height: 20),
              Text('Sign-in cookies now', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<SignInCookieReport?>(
                future: _cookies,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox.shrink();
                  }
                  final report = snapshot.data;
                  if (report == null) return Text('Not available on this device.', style: muted);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CookieList(report.cookies),
                      if (report.savedCount != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Saved for the next launch: ${report.savedCount} cookies'
                            '${report.savedAt == null ? '' : ', at ${_time.format(report.savedAt!)}'}',
                            style: muted,
                          ),
                        ),
                      if (report.restoredAtLaunch != null)
                        Text('Restored at this launch: ${report.restoredAtLaunch} cookies',
                            style: muted),
                      if (report.putBackCount != null)
                        Text(
                          'Last put back after going missing: ${report.putBackCount} cookies, '
                          'at ${_time.format(report.putBackAt!)}',
                          style: muted,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('Recent attempts', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (widget.log.attempts.isEmpty) Text('Nothing recorded yet.', style: muted),
              for (final attempt in widget.log.attempts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${attempt.trigger} · ${_time.format(attempt.startedAt)}',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(attempt.outcome ?? 'unfinished',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        for (final step in attempt.steps) Text(step, style: muted),
                        if (attempt.cookies != null) ...[
                          const SizedBox(height: 6),
                          Text('Cookies afterwards', style: theme.textTheme.labelMedium),
                          _CookieList(attempt.cookies!),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CookieList extends StatelessWidget {
  const _CookieList(this.cookies);

  final List<SignInCookie> cookies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (cookies.isEmpty) return Text('No sign-in cookies.', style: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cookie in cookies)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: cookie.name,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: ' · ${cookie.host} · ${cookie.lifetime}'
                      '${cookie.meaning == null ? '' : ' · ${cookie.meaning}'}',
                  style: muted,
                ),
              ]),
            ),
          ),
      ],
    );
  }
}
