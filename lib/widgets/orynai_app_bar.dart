import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';

/// Цвет фона хедера: rgba(250, 247, 238, 0.85)
const _kHeaderBg = Color.fromRGBO(250, 247, 238, 1);

/// Цвет нижней границы: rgba(0, 0, 0, 0.08)
const _kHeaderBorder = Color(0x14000000);

/// Универсальный AppBar приложения.
///
/// Использование:
/// ```dart
/// // Главная страница (с лого, меню пользователя)
/// appBar: OrynaiAppBar(title: 'Кабинет менеджера', showLogo: true, actions: [...])
///
/// // Внутренняя страница (с кнопкой назад)
/// appBar: OrynaiAppBar(title: 'Название', showBack: true)
/// ```
class OrynaiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Показывать SVG-лого перед заголовком
  final bool showLogo;

  /// Показывать кнопку «Назад» слева (для вложенных страниц)
  final bool showBack;

  /// Дополнительные кнопки справа
  final List<Widget> actions;

  const OrynaiAppBar({
    super.key,
    required this.title,
    this.showLogo = false,
    this.showBack = false,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kHeaderBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            backgroundColor: _kHeaderBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: showBack
                ? IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.iconAndText,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLogo) ...[
                  SvgPicture.asset(
                    'assets/images/logos/logo.svg',
                    height: 26,
                    width: 26,
                    colorFilter: const ColorFilter.mode(
                      AppColors.iconAndText,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.iconAndText,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            actions: actions,
          ),
          // Нижняя граница: 1px solid rgba(0,0,0,0.08)
          Container(height: 1, color: _kHeaderBorder),
        ],
      ),
    );
  }
}
