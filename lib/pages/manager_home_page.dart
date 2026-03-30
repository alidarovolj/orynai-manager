import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/cemetery_service.dart';
import '../services/auth_state_manager.dart';
import '../services/sync_service.dart';
import 'grave_detail_page.dart';
import 'manager_login_page.dart';
import 'manager_map_page.dart';
import 'manager_profile_page.dart';
import 'place_booking_page.dart';

class ManagerHomePage extends StatefulWidget {
  const ManagerHomePage({super.key});

  @override
  State<ManagerHomePage> createState() => _ManagerHomePageState();
}

class _ManagerHomePageState extends State<ManagerHomePage> {
  final CemeteryService _cemeteryService = CemeteryService();
  final AuthStateManager _authManager = AuthStateManager();
  final SyncService _syncService = SyncService();

  List<Cemetery> _cemeteries = [];
  Cemetery? _selectedCemetery;
  /// Выбранное на карте место (сайдбар с деталями и бронью).
  Grave? _selectedGrave;
  bool _isLoading = true; // true только пока кэш полностью пуст
  bool _isRefreshing = false; // true во время фонового обновления с сервера
  String? _refreshError; // ошибка последнего обновления с сервера
  DateTime? _cachedAt; // когда последний раз получили данные
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    _syncService.start();
    _loadCemeteries();
  }

  @override
  void dispose() {
    _syncService.stop();
    super.dispose();
  }

  /// Загрузка: сначала кэш (мгновенно), затем сеть (в фоне).
  /// Оставляет текущий выбор, если кладбище ещё в списке, иначе — первое.
  void _syncSelectionWithList() {
    if (_cemeteries.isEmpty) {
      _selectedCemetery = null;
      _selectedGrave = null;
      return;
    }
    final cur = _selectedCemetery;
    if (cur != null && _cemeteries.any((c) => c.id == cur.id)) {
      return;
    }
    _selectedCemetery = _cemeteries.first;
    _selectedGrave = null;
  }

  Future<void> _loadCemeteries() async {
    // 1. Показываем кэш немедленно
    final cached = await _cemeteryService.getCachedCemeteries();
    final cachedAt = await _cemeteryService.getCemeteriesCachedAt();
    if (mounted) {
      setState(() {
        if (cached.isNotEmpty) {
          _cemeteries = cached;
          _cachedAt = cachedAt;
          _isLoading = false; // есть хоть что-то — убираем полный лоадер
          _syncSelectionWithList();
        }
        _isRefreshing = true; // всегда пробуем обновить с сервера
        _refreshError = null;
      });
    }

    // 2. Пытаемся обновить с сервера
    try {
      final fresh = await _cemeteryService.fetchCemeteriesFromNetwork();
      if (mounted) {
        setState(() {
          _cemeteries = fresh;
          _cachedAt = DateTime.now();
          _isLoading = false;
          _isRefreshing = false;
          _refreshError = null;
          _syncSelectionWithList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          // Показываем ошибку только если кэш тоже пуст
          _refreshError = cached.isEmpty
              ? 'Нет данных. Проверьте подключение к интернету.'
              : 'Не удалось обновить данные. Показаны сохранённые.';
        });
      }
    }
  }

  /// Принудительное обновление с сервера (pull-to-refresh / кнопка).
  Future<void> _refreshCemeteries() async {
    setState(() {
      _isRefreshing = true;
      _refreshError = null;
    });
    try {
      final fresh = await _cemeteryService.fetchCemeteriesFromNetwork();
      if (mounted) {
        setState(() {
          _cemeteries = fresh;
          _cachedAt = DateTime.now();
          _isRefreshing = false;
          _refreshError = null;
          _syncSelectionWithList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshError = 'Не удалось обновить: нет подключения.';
        });
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    await _syncService.syncNow();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Синхронизация завершена'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.buttonBackground,
            ),
            child: const Text('Выйти', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _authManager.logout();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ManagerLoginPage()),
      );
    }
  }

  String _getReligionIconPath(Cemetery c) {
    return c.religion == 'Ислам'
        ? 'assets/icons/religions/003-islam.svg'
        : 'assets/icons/religions/christianity.svg';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _authManager.getDisplayName();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logos/main.png',
              height: 32,
              errorBuilder: (_, __, ___) => const SizedBox(width: 32),
            ),
            const SizedBox(width: 8),
            const Text(
              'Менеджер',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.iconAndText,
              ),
            ),
          ],
        ),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.buttonBackground,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, color: AppColors.iconAndText),
              tooltip: 'Синхронизировать',
              onPressed: _syncNow,
            ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'logout') _logout();
              if (val == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManagerProfilePage()),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'info',
                enabled: false,
                child: Text(
                  displayName.isNotEmpty ? displayName : 'Менеджер',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.iconAndText,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 18, color: AppColors.iconAndText),
                    SizedBox(width: 8),
                    Text('Профиль'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Выйти', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.iconAndText, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName.isNotEmpty ? displayName : 'Менеджер',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.iconAndText,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.iconAndText),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingMedium,
              AppSizes.paddingMedium,
              AppSizes.paddingMedium,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Кладбища',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.iconAndText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Выберите кладбище для работы',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.iconAndText.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          // Строка статуса (кэш / обновление / ошибка)
          _buildStatusBar(),

          // Основной контент
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    if (_isRefreshing) {
      return Container(
        width: double.infinity,
        color: AppColors.buttonGreen.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.buttonGreen,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Обновление данных...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.buttonGreen.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      );
    }

    if (_refreshError != null) {
      return Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 14, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _refreshError!,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            GestureDetector(
              onTap: _refreshCemeteries,
              child: const Text(
                'Повторить',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_cachedAt != null) {
      final diff = DateTime.now().difference(_cachedAt!);
      final label = diff.inMinutes < 1
          ? 'только что'
          : diff.inHours < 1
          ? '${diff.inMinutes} мин. назад'
          : diff.inDays < 1
          ? '${diff.inHours} ч. назад'
          : '${diff.inDays} д. назад';
      return Container(
        width: double.infinity,
        color: Colors.green.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          'Данные обновлены $label',
          style: TextStyle(fontSize: 11, color: Colors.green.shade700),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.buttonBackground),
      );
    }

    if (_cemeteries.isEmpty && _refreshError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off,
                size: 48,
                color: AppColors.iconAndText,
              ),
              const SizedBox(height: 16),
              Text(
                _refreshError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.iconAndText),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
                onPressed: _loadCemeteries,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonBackground,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_cemeteries.isEmpty) {
      return const Center(
        child: Text(
          'Нет доступных кладбищ',
          style: TextStyle(color: AppColors.iconAndText),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final listW = (w * 0.36)
            .clamp(200.0, min(400.0, w * 0.46))
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listW,
              child: _buildSidebarContent(),
            ),
            Expanded(child: _buildMapPanel()),
          ],
        );
      },
    );
  }

  Widget _buildSidebarContent() {
    final c = _selectedCemetery;
    final g = _selectedGrave;
    if (g != null && c != null) {
      return _SelectedPlaceSidebar(
        cemetery: c,
        grave: g,
        religionIconPath: _getReligionIconPath(c),
        onBackToList: () => setState(() => _selectedGrave = null),
        onBook: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaceBookingPage(cemetery: c, grave: g),
            ),
          );
        },
        onOpenManagerCard: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GraveDetailPage(cemetery: c, grave: g),
            ),
          );
        },
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _refreshCemeteries,
        color: AppColors.buttonBackground,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          itemCount: _cemeteries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final cemetery = _cemeteries[index];
            final selected = cemetery.id == _selectedCemetery?.id;
            return _CemeteryCard(
              cemetery: cemetery,
              iconPath: _getReligionIconPath(cemetery),
              selected: selected,
              onTap: () {
                setState(() {
                  _selectedCemetery = cemetery;
                  _selectedGrave = null;
                });
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMapPanel() {
    if (_selectedCemetery == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text(
            'Выберите кладбище',
            style: TextStyle(color: AppColors.iconAndText),
          ),
        ),
      );
    }
    return ClipRect(
      child: ManagerMapPage(
        key: ValueKey(_selectedCemetery!.id),
        cemetery: _selectedCemetery!,
        embedded: true,
        selectedGrave: _selectedGrave,
        onSelectedGraveChanged: (grave) {
          setState(() => _selectedGrave = grave);
        },
      ),
    );
  }
}

class _SelectedPlaceSidebar extends StatelessWidget {
  final Cemetery cemetery;
  final Grave grave;
  final String religionIconPath;
  final VoidCallback onBackToList;
  final VoidCallback onBook;
  final VoidCallback onOpenManagerCard;

  const _SelectedPlaceSidebar({
    required this.cemetery,
    required this.grave,
    required this.religionIconPath,
    required this.onBackToList,
    required this.onBook,
    required this.onOpenManagerCard,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'free':
        return 'Свободно';
      case 'reserved':
        return 'Забронировано';
      case 'occupied':
        return 'Захоронено';
      default:
        return 'Резерв';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'free':
        return Colors.green;
      case 'reserved':
        return Colors.orange;
      case 'occupied':
        return Colors.grey.shade600;
      default:
        return Colors.blue.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final desc = cemetery.description.trim();
    final canBook = grave.isFree;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF7EE),
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSizes.paddingMedium),
              children: [
                TextButton.icon(
                  onPressed: onBackToList,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: AppColors.buttonBackground,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text(
                    'Вернуться к списку кладбищ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SvgPicture.asset(
                      religionIconPath,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        AppColors.iconAndText,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (_) => const Icon(
                        Icons.place,
                        size: 24,
                        color: AppColors.iconAndText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cemetery.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.iconAndText,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.iconAndText.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${cemetery.city}, ${cemetery.streetName}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.iconAndText.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
                if (cemetery.phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    cemetery.phone,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.iconAndText.withValues(alpha: 0.75),
                    ),
                  ),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.iconAndText.withValues(alpha: 0.88),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(AppSizes.paddingMedium),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F0E7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Сектор: ${grave.sectorNumber}   Ряд: ${grave.rowNumber}   Место: ${grave.graveNumber}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.iconAndText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _statusColor(grave.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _statusLabel(grave.status),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(grave.status),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.paddingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canBook)
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: onBook,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.buttonBackground,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 22),
                      label: const Text(
                        'Забронировать место',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    grave.isOccupied
                        ? 'Место занято. Бронирование недоступно.'
                        : 'Место в статусе «${_statusLabel(grave.status)}». Для действий откройте карточку.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.iconAndText.withValues(alpha: 0.75),
                    ),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: onOpenManagerCard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.iconAndText,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Карточка менеджера',
                    style: TextStyle(fontWeight: FontWeight.w600),
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

class _CemeteryCard extends StatelessWidget {
  final Cemetery cemetery;
  final String iconPath;
  final bool selected;
  final VoidCallback onTap;

  const _CemeteryCard({
    required this.cemetery,
    required this.iconPath,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.buttonBackground.withValues(alpha: 0.12)
          : const Color(0xFFF4F0E7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.buttonBackground : Colors.transparent,
              width: selected ? 2 : 0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingMedium),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.buttonBackground.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      iconPath,
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        AppColors.iconAndText,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (_) =>
                          const Icon(Icons.place, color: AppColors.iconAndText),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cemetery.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.iconAndText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cemetery.streetName}, ${cemetery.city}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.iconAndText.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.chevron_right,
                  color: selected
                      ? AppColors.buttonBackground
                      : AppColors.iconAndText,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
