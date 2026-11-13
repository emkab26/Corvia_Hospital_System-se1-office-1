import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'corvia_logo.dart';

/// One entry in the staff sidebar. Items with [selected] mark the current
/// page; the others usually open a screen or run an action.
class StaffShellItem {
  const StaffShellItem({
    required this.label,
    required this.icon,
    this.onTap,
    this.selected = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool busy;
}

/// The hospital-admin layout (blue sidebar, header bar, content) shared by
/// the reception, nurse, pharmacist and laboratory dashboards so every staff
/// workspace looks and navigates the same way.
///
/// From 1050 px wide the sidebar is always visible; below that it moves into
/// a drawer opened from the header's menu button.
class StaffWorkspaceShell extends StatefulWidget {
  const StaffWorkspaceShell({
    super.key,
    required this.workspaceName,
    required this.breadcrumb,
    required this.pageTitle,
    required this.items,
    required this.body,
    this.subtitle,
    this.headerActions = const [],
    this.onSignOut,
  });

  /// Shown under "Corvia" in the sidebar, e.g. "Reception Desk".
  final String workspaceName;

  /// Header prefix, e.g. "Reception" gives "Reception / Dashboard".
  final String breadcrumb;
  final String pageTitle;
  final String? subtitle;
  final List<StaffShellItem> items;
  final List<Widget> headerActions;
  final VoidCallback? onSignOut;
  final Widget body;

  @override
  State<StaffWorkspaceShell> createState() => _StaffWorkspaceShellState();
}

class _StaffWorkspaceShellState extends State<StaffWorkspaceShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;

        if (isWide) {
          return Scaffold(
            backgroundColor: context.cBgPrimary,
            body: SafeArea(
              child: Row(
                children: [
                  _Sidebar(shell: widget),
                  Expanded(
                    child: Column(
                      children: [
                        _Header(shell: widget),
                        Expanded(child: widget.body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: context.cBgPrimary,
          drawer: Drawer(
            backgroundColor: Colors.transparent,
            child: SafeArea(child: _Sidebar(shell: widget, compact: true)),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _Header(
                  shell: widget,
                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                Expanded(child: widget.body),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shell, this.onMenu});

  final StaffWorkspaceShell shell;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        final title = Row(
          children: [
            if (onMenu != null) ...[
              Material(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(12),
                child: IconButton(
                  tooltip: 'Menu',
                  onPressed: onMenu,
                  icon: Icon(Icons.menu_rounded,
                      color: context.cAccentReadable),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shell.breadcrumb} / ${shell.pageTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (shell.subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      shell.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.cTextSecondary, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: shell.headerActions,
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            border: Border(bottom: BorderSide(color: context.cDivider)),
          ),
          child: compact || shell.headerActions.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (shell.headerActions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      actions,
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.shell, this.compact = false});

  final StaffWorkspaceShell shell;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sidebarColor = context.isDarkTheme
        ? Color.alphaBlend(
            CorviaColors.accentDark.withValues(alpha: 0.28),
            context.cBgPrimary,
          )
        : CorviaColors.accentDark;

    void run(StaffShellItem item) {
      if (compact) Navigator.of(context).pop();
      item.onTap?.call();
    }

    return Container(
      width: compact ? 285 : 270,
      color: sidebarColor,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const CorviaLogo(size: 30, badge: true),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Corvia',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shell.workspaceName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT PAGE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  shell.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: shell.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) => _SidebarTile(
                item: shell.items[index],
                onTap: () => run(shell.items[index]),
              ),
            ),
          ),
          if (shell.onSignOut != null) ...[
            const SizedBox(height: 8),
            _SidebarTile(
              item: StaffShellItem(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                onTap: shell.onSignOut,
              ),
              onTap: () => run(
                StaffShellItem(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  onTap: shell.onSignOut,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Secure hospital workspace',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.item, required this.onTap});

  final StaffShellItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = item.selected;
    final enabled = item.onTap != null && !item.busy;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.30)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              item.busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      item.icon,
                      size: 21,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.72),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.84),
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
