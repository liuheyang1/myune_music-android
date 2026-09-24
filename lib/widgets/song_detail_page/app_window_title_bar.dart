import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../../page/setting/settings_provider.dart';

class AppWindowTitleBar extends StatelessWidget {
  final VoidCallback onSettingsPressed;
  final bool showBackButton;
  final bool showSettingsButton;
  final VoidCallback? onNavigationPressed;

  const AppWindowTitleBar({
    super.key,
    required this.onSettingsPressed,
    this.showBackButton = true,
    this.showSettingsButton = true,
    this.onNavigationPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Container(
      height: isDesktop ? 31.0 : 48.0,
      decoration: const BoxDecoration(
        color: Colors.transparent, // 透明背景以显示模糊效果
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (showBackButton)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.arrow_back,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    tooltip: '返回',
                    padding: EdgeInsets.zero,
                  ),
                if (showSettingsButton)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz),
                    onPressed: onSettingsPressed,
                    tooltip: '歌词设置',
                    padding: EdgeInsets.zero,
                  ),
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/icon/icon.png',
                    width: 21,
                    height: 21,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "MyuneMusic",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (isDesktop)
            Expanded(child: DragToMoveArea(child: Container()))
          else
            const Spacer(),
          if (!isDesktop && onNavigationPressed != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: '功能菜单',
                visualDensity: VisualDensity.compact,
                onPressed: onNavigationPressed,
                icon: const Icon(Icons.apps_rounded),
              ),
            ),
          if (isDesktop)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WindowButton(
                    icon: Icons.remove,
                    onPressed: () {
                      final settings = Provider.of<SettingsProvider>(
                        context,
                        listen: false,
                      );
                      if (settings.minimizeToTray) {
                        windowManager.hide();
                      } else {
                        windowManager.minimize();
                      }
                    },
                    hoverColor: const Color.fromRGBO(144, 202, 249, 1),
                  ),
                  const SizedBox(width: 2),
                  _WindowButton(
                    icon: Icons.crop_square,
                    onPressed: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                    hoverColor: const Color.fromRGBO(144, 202, 249, 1),
                  ),
                  const SizedBox(width: 2),
                  _WindowButton(
                    icon: Icons.close,
                    onPressed: () => windowManager.close(),
                    hoverColor: const Color.fromRGBO(239, 154, 154, 1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color hoverBackgroundColor;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor = const Color(0xFF404040),
    // ignore: unused_element_parameter
    this.hoverBackgroundColor = Colors.transparent,
  });

  @override
  _WindowButtonState createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color defaultIconColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) {
        setState(() {
          _isHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          _isHovering = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHovering
                ? (widget.hoverBackgroundColor)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Icon(
            widget.icon,
            color: _isHovering ? widget.hoverColor : defaultIconColor,
            size: 20,
          ),
        ),
        onTapDown: (_) {}, // 空的回调，用于确保GestureDetector在某些情况下能正确响应
      ),
    );
  }
}
