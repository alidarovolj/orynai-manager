import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';
import '../services/auth_state_manager.dart';

class AppHeader extends StatelessWidget {
  final bool isScrolled;
  final VoidCallback? onMenuTap;
  final VoidCallback? onProfileTap;

  const AppHeader({
    super.key,
    required this.isScrolled,
    this.onMenuTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = AppColors.iconAndText;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            // boxShadow: [
            //   BoxShadow(
            //     color: Colors.black.withValues(alpha: 0.1),
            //     blurRadius: 10,
            //     offset: const Offset(0, 4), // Тень только снизу
            //     spreadRadius: 0,
            //   ),
            // ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingMedium,
            vertical: 12.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Иконка меню слева
              IconButton(
                icon: SvgPicture.asset(
                  'assets/icons/menu.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  placeholderBuilder: (BuildContext context) => Container(
                    width: 24,
                    height: 24,
                    color: Colors.transparent,
                  ),
                ),
                onPressed: onMenuTap,
              ),
              // Логотип по центру
              SvgPicture.asset(
                'assets/images/logos/logo.svg',
                width: 40,
                height: 40,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                placeholderBuilder: (BuildContext context) =>
                    Container(width: 40, height: 40, color: Colors.transparent),
              ),
              // Иконка профиля или имя пользователя справа
              _buildProfileButton(context, iconColor),
            ],
          ),
        ),
        // Поле поиска
        // AnimatedContainer(
        //   duration: const Duration(milliseconds: 300),
        //   color: headerColor,
        //   padding: const EdgeInsets.fromLTRB(
        //     AppSizes.paddingMedium,
        //     0,
        //     AppSizes.paddingMedium,
        //     12.0,
        //   ),
        //   child: Container(
        //     decoration: BoxDecoration(
        //       color: Colors.white,
        //       borderRadius: BorderRadius.circular(24),
        //       border: Border.all(
        //         color: AppColors.accordionBorder.withOpacity(0.3),
        //         width: 1,
        //       ),
        //     ),
        //     child: TextField(
        //       decoration: InputDecoration(
        //         hintText: 'header.searchPlaceholder'.tr(),
        //         hintStyle: TextStyle(
        //           color: AppColors.iconAndText.withOpacity(0.5),
        //           fontSize: 14,
        //         ),
        //         prefixIcon: Icon(
        //           Icons.search,
        //           color: AppColors.iconAndText,
        //           size: 20,
        //         ),
        //         border: InputBorder.none,
        //         contentPadding: const EdgeInsets.symmetric(
        //           horizontal: 16,
        //           vertical: 12,
        //         ),
        //       ),
        //       style: const TextStyle(
        //         fontSize: 14,
        //         color: AppColors.iconAndText,
        //       ),
        //       onTap: () {
        //         // TODO: Реализовать поиск
        //       },
        //     ),
        //   ),
        // ),
      ],
    );
  }

  Widget _buildProfileButton(BuildContext context, Color iconColor) {
    final authManager = AuthStateManager();
    final isAuthenticated = authManager.isAuthenticated;
    final displayName = authManager.getDisplayName();

    return IconButton(
      icon: isAuthenticated && displayName.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: iconColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                border: Border.all(color: iconColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(2),
              child: SvgPicture.asset(
                'assets/icons/person.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                placeholderBuilder: (BuildContext context) =>
                    Container(width: 20, height: 20, color: Colors.transparent),
              ),
            ),
      onPressed: onProfileTap,
    );
  }
}
