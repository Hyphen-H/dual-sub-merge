import 'package:flutter/material.dart';

import '../models/merge_options.dart';

class UiTokens {
  const UiTokens._();

  static const sidebarWidth = 220.0;
  static const sidebarCompactWidth = 76.0;
  static const pageMaxWidth = 1440.0;
  static const pagePadding = 28.0;
  static const pagePaddingCompact = 12.0;
  static const sectionGap = 16.0;
  static const border = Color(0xFFDDE2EA);
  static const canvas = Color(0xFFF5F7FA);
  static const subtle = Color(0xFFFAFBFC);
  static const muted = Color(0xFF657083);
  static const success = Color(0xFF278064);
  static const successBg = Color(0xFFE9F6F1);
  static const warning = Color(0xFF9A6819);
  static const warningBg = Color(0xFFFFF4DE);
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        border: Border.all(color: UiTokens.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x090F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.description,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 5),
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: UiTokens.muted),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 20), trailing!],
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (description != null) ...[
                const SizedBox(height: 3),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class SidebarNavItem extends StatefulWidget {
  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<SidebarNavItem> {
  static const _duration = Duration(milliseconds: 120);
  static const _ink = Color(0xFF18202F);

  bool _hovered = false;
  bool _pressed = false;

  Color get _background {
    if (widget.selected) {
      final primary = Theme.of(context).colorScheme.primary;
      if (_pressed) return primary.withValues(alpha: 0.20);
      if (_hovered) return primary.withValues(alpha: 0.16);
      return primary.withValues(alpha: 0.12);
    }
    if (_pressed) return _ink.withValues(alpha: 0.08);
    if (_hovered) return _ink.withValues(alpha: 0.05);
    return Colors.transparent;
  }

  Color get _foreground {
    final scheme = Theme.of(context).colorScheme;
    if (widget.selected) return scheme.primary;
    if (_hovered || _pressed) return scheme.onSurface;
    return scheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final fg = _foreground;

    final row = AnimatedContainer(
      duration: _duration,
      curve: Curves.easeOut,
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment:
            compact ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(widget.icon, size: 18, color: fg),
          if (!compact) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight:
                      widget.selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final hit = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: row,
      ),
    );

    if (!compact) return hit;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 450),
      child: hit,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class ResolutionPicker extends StatefulWidget {
  const ResolutionPicker({
    super.key,
    required this.index,
    required this.onChanged,
    this.enabled = true,
    this.presets = ResolutionPreset.list,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final List<ResolutionPreset> presets;

  @override
  State<ResolutionPicker> createState() => _ResolutionPickerState();
}

class _ResolutionPickerState extends State<ResolutionPicker> {
  static const _duration = Duration(milliseconds: 120);
  static const _ink = Color(0xFF18202F);

  bool _hovered = false;
  bool _pressed = false;
  bool _menuOpen = false;

  int get _index =>
      widget.index.clamp(0, widget.presets.isEmpty ? 0 : widget.presets.length - 1);

  ResolutionPreset get _current => widget.presets[_index];

  Color _triggerBackground(ColorScheme scheme, bool enabled) {
    if (!enabled) return scheme.surface;
    final primary = scheme.primary;
    if (_menuOpen) {
      if (_pressed) return primary.withValues(alpha: 0.20);
      if (_hovered) return primary.withValues(alpha: 0.16);
      return primary.withValues(alpha: 0.12);
    }
    if (_pressed) return _ink.withValues(alpha: 0.08);
    if (_hovered) return _ink.withValues(alpha: 0.05);
    return scheme.surface;
  }

  Color _triggerForeground(ColorScheme scheme, bool enabled) {
    if (!enabled) return Theme.of(context).disabledColor;
    if (_menuOpen) return scheme.primary;
    if (_hovered || _pressed) return scheme.onSurface;
    return scheme.onSurfaceVariant;
  }

  Color _triggerMuted(ColorScheme scheme, bool enabled) {
    if (!enabled) return Theme.of(context).disabledColor;
    if (_menuOpen) return scheme.primary.withValues(alpha: 0.75);
    if (_hovered || _pressed) return scheme.onSurfaceVariant;
    return UiTokens.muted;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;

    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: Offset.zero,
      onOpen: () {
        if (!_menuOpen) setState(() => _menuOpen = true);
      },
      onClose: () {
        if (_menuOpen || _hovered || _pressed) {
          setState(() {
            _menuOpen = false;
            _hovered = false;
            _pressed = false;
          });
        }
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: const WidgetStatePropertyAll(Color(0x1A18202F)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: UiTokens.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        visualDensity: VisualDensity.standard,
      ),
      builder: (context, controller, _) {
        final open = _menuOpen || controller.isOpen;
        final fg = _triggerForeground(scheme, enabled);
        final muted = _triggerMuted(scheme, enabled);

        void toggle() {
          if (!enabled) return;
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open(position: Offset.zero);
          }
        }

        return MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) {
            if (enabled) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (_) => setState(() => _pressed = true)
                : null,
            onTapUp: enabled
                ? (_) => setState(() => _pressed = false)
                : null,
            onTapCancel: enabled
                ? () => setState(() => _pressed = false)
                : null,
            onTap: enabled ? toggle : null,
            child: AnimatedContainer(
              duration: _duration,
              curve: Curves.easeOut,
              height: 40,
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              decoration: BoxDecoration(
                color: _triggerBackground(scheme, enabled),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UiTokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.aspect_ratio_rounded, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _current.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        _current.pixelsLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.15,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: _duration,
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        for (var i = 0; i < widget.presets.length; i++)
          _ResolutionMenuItem(
            preset: widget.presets[i],
            selected: i == _index,
            enabled: enabled,
            onTap: () => widget.onChanged(i),
          ),
      ],
    );
  }
}

class _ResolutionMenuItem extends StatefulWidget {
  const _ResolutionMenuItem({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ResolutionPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ResolutionMenuItem> createState() => _ResolutionMenuItemState();
}

class _ResolutionMenuItemState extends State<_ResolutionMenuItem> {
  static const _duration = Duration(milliseconds: 120);
  static const _ink = Color(0xFF18202F);

  bool _hovered = false;
  bool _pressed = false;

  Color _background(ColorScheme scheme) {
    if (widget.selected) {
      final primary = scheme.primary;
      if (_pressed) return primary.withValues(alpha: 0.20);
      if (_hovered) return primary.withValues(alpha: 0.16);
      return primary.withValues(alpha: 0.12);
    }
    if (_pressed) return _ink.withValues(alpha: 0.08);
    if (_hovered) return _ink.withValues(alpha: 0.05);
    return Colors.transparent;
  }

  Color _titleColor(ColorScheme scheme) {
    if (widget.selected) return scheme.primary;
    if (_hovered || _pressed) return scheme.onSurface;
    return scheme.onSurface;
  }

  Color _subColor(ColorScheme scheme) {
    if (widget.selected) return scheme.primary.withValues(alpha: 0.75);
    if (_hovered || _pressed) return scheme.onSurfaceVariant;
    return UiTokens.muted;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final titleColor = _titleColor(scheme);
    final subColor = _subColor(scheme);

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.enabled) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.enabled
            ? (_) => setState(() => _pressed = false)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _pressed = false)
            : null,
        onTap: widget.enabled
            ? () {
                widget.onTap();
                MenuController.maybeOf(context)?.close();
              }
            : null,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          width: 156,
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: _background(scheme),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.preset.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: titleColor,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.preset.pixelsLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: subColor,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 16, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 48,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [...actions, const SizedBox(width: 20)],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: child,
    );
  }
}
