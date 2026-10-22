import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/data/network_status.dart';
import 'package:illini_dining/state/reconnector.dart';

void main() {
  late NetworkStatus status;
  late int attempts;
  late bool succeed;
  late StreamController<Object?> connectivity;
  late Reconnector reconnector;

  // testWidgets for fake timers and a WidgetsBinding.
  void setUpReconnector() {
    status = NetworkStatus();
    attempts = 0;
    succeed = false;
    connectivity = StreamController<Object?>();
    reconnector = Reconnector(
      status: status,
      connectivityChanges: connectivity.stream,
      retry: () async {
        attempts++;
        succeed ? status.reportSuccess() : status.reportFailure();
      },
    );
    addTearDown(() {
      reconnector.dispose();
      connectivity.close();
    });
  }

  testWidgets('does nothing while online', (tester) async {
    setUpReconnector();
    connectivity.add('wifi');
    await tester.pump(const Duration(minutes: 5));
    expect(attempts, 0);
  });

  testWidgets('retries on a backing-off timer while offline', (tester) async {
    setUpReconnector();
    status.reportFailure();
    await tester.pump(const Duration(seconds: 14));
    expect(attempts, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 1, reason: 'first retry after 15s');
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 2, reason: 'then 30s later');
    await tester.pump(const Duration(seconds: 60));
    expect(attempts, 3, reason: 'then 60s later');

    succeed = true;
    await tester.pump(const Duration(minutes: 2));
    expect(attempts, 4);
    expect(status.online, isTrue);
    await tester.pump(const Duration(minutes: 10));
    expect(attempts, 4, reason: 'stops once back online');
  });

  testWidgets('retries right away when the connection changes', (tester) async {
    setUpReconnector();
    status.reportFailure();
    succeed = true;
    connectivity.add('wifi');
    await tester.pump();
    expect(attempts, 1);
    expect(status.online, isTrue);
  });

  testWidgets('retries when the app returns to the foreground', (tester) async {
    setUpReconnector();
    status.reportFailure();
    succeed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(attempts, 1);
    expect(status.online, isTrue);
  });
}
