import 'package:flutter/material.dart';

/// Keeps pushed pages inside a dashboard's content area. App-level actions
/// such as switching dashboards and signing out keep using the outer navigator.
mixin WorkspaceNavigation<T extends StatefulWidget> on State<T> {
  final _workspaceNavigatorKey = GlobalKey<NavigatorState>();
  final _workspaceRoutes = <Route<dynamic>>[];
  final _workspaceLabels = <Route<dynamic>, String>{};
  late final _workspaceObserver = _WorkspaceObserver(
    routes: _workspaceRoutes,
    onChanged: _workspaceChanged,
  );
  bool _workspaceUpdateScheduled = false;

  bool get workspaceCanPop => _workspaceRoutes.length > 1;

  String? get workspaceSelection {
    for (final route in _workspaceRoutes.skip(1)) {
      final label = _workspaceLabels[route] ?? route.settings.name;
      if (label != null) return label;
    }
    return null;
  }

  String? get workspaceTitle {
    for (final route in _workspaceRoutes.skip(1).toList().reversed) {
      final label = _workspaceLabels[route] ?? route.settings.name;
      if (label != null) return label;
    }
    return null;
  }

  /// A context below the content navigator, for existing navigation helpers.
  BuildContext get workspaceContext =>
      _workspaceNavigatorKey.currentState!.overlay!.context;

  Future<R?> pushWorkspace<R>(Route<R> route, {required String label}) {
    // Menu entries replace the current section; Back returns to the dashboard
    // in one step. Further navigation from a child stays in this navigator.
    workspaceHome();
    _workspaceLabels[route] = label;
    return _workspaceNavigatorKey.currentState!.push(route);
  }

  void workspaceHome() {
    _workspaceNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  void workspaceBack() => _workspaceNavigatorKey.currentState?.maybePop();

  Widget get workspaceBackButton => OutlinedButton.icon(
        onPressed: workspaceBack,
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Back'),
      );

  Widget workspaceBody(Widget home) => _WorkspaceHome(
        home: home,
        child: NavigatorPopHandler<Object?>(
          onPopWithResult: (result) =>
              _workspaceNavigatorKey.currentState?.pop(result),
          child: Navigator(
            key: _workspaceNavigatorKey,
            observers: [_workspaceObserver],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => _WorkspaceHome.of(context),
            ),
          ),
        ),
      );

  void _workspaceChanged() {
    if (_workspaceUpdateScheduled) return;
    _workspaceUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceUpdateScheduled = false;
      if (!mounted) return;
      _workspaceLabels
          .removeWhere((route, _) => !_workspaceRoutes.contains(route));
      setState(() {});
    });
  }
}

class _WorkspaceHome extends InheritedWidget {
  const _WorkspaceHome({required this.home, required super.child});
  final Widget home;

  static Widget of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WorkspaceHome>()!.home;

  @override
  bool updateShouldNotify(_WorkspaceHome oldWidget) => home != oldWidget.home;
}

class _WorkspaceObserver extends NavigatorObserver {
  _WorkspaceObserver({required this.routes, required this.onChanged});
  final List<Route<dynamic>> routes;
  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        routes.removeAt(index);
      } else {
        routes[index] = newRoute;
      }
    }
    onChanged();
  }
}
