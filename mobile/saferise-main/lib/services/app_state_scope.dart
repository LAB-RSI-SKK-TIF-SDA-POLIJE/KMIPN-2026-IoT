import 'package:flutter/widgets.dart';
import 'app_state.dart';

/// Lightweight DI: avoids pulling in the `provider` package for an MVP.
/// Usage: AppStateScope.of(context).cameras
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState appState,
    required super.child,
  }) : super(notifier: appState);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in context');
    return scope!.notifier!;
  }
}
