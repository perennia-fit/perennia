import 'package:flutter/material.dart';

/// Root navigation handles, wired into the app's [MaterialApp].
///
/// A [GlobalKey] navigator lets background services (e.g. the timer
/// notification router) push routes and resolve the current route
/// without a [BuildContext]. The scaffold-messenger key shows SnackBars from
/// the same context-free callers.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'rootScaffoldMessenger');
