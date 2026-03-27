import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';
import '../models/cemetery.dart';
import '../services/cemetery_service.dart';
import '../services/auth_state_manager.dart';
import '../services/sync_service.dart';
import 'manager_login_page.dart';
import 'manager_map_page.dart';

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
  bool _isLoading = true;       // true только пока кэш полностью пуст
  bool _isRefreshing = false;   // true во время фонового обновления с сервера
  String? _refreshError;        // ошибка последнего обновления с сервера
  DateTime? _cachedAt;          // когда последний раз получили данные
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
  Future<void> _loadCemeteries() async {
    // 1. Показываем кэш немедленно
    final cached = await _cemeteryService.getCachedCemeteries();
    final cachedAt = await _cemeteryService.getCemeteriesCachedAt();
    if (mounted) {
      setState(() {
        if (cached.isNotEmpty) {
          _cemeteries = cached;
          _cachedAt = cachedAt;
          _isLoading = false;     // есть хоть что-то — убираем полный лоадер
        }
        _isRefreshing = true;     // всегда пробуем обновить с сервера
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
            icon: const Icon(Icons.more_vert, color: AppColors.iconAndText),
            onSelected: (val) {
              if (val == 'logout') _logout();
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
          Expanded(
            child: _buildBody(),
          ),
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
          style: TextStyle(
            fontSize: 11,
            color: Colors.green.shade700,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.buttonBackground,
        ),
      );
    }

    if (_cemeteries.isEmpty && _refreshError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: AppColors.iconAndText),
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

    return RefreshIndicator(
      onRefresh: _refreshCemeteries,
      color: AppColors.buttonBackground,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSizes.paddingMedium),
        itemCount: _cemeteries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final cemetery = _cemeteries[index];
          return _CemeteryCard(
            cemetery: cemetery,
            iconPath: _getReligionIconPath(cemetery),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManagerMapPage(cemetery: cemetery),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CemeteryCard extends StatelessWidget {
  final Cemetery cemetery;
  final String iconPath;
  final VoidCallback onTap;

  const _CemeteryCard({
    required this.cemetery,
    required this.iconPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F0E7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                    placeholderBuilder: (_) => const Icon(
                      Icons.place,
                      color: AppColors.iconAndText,
                    ),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusChip(
                          color: Colors.green,
                          count: cemetery.freeSpaces,
                          label: 'свободно',
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(
                          color: Colors.orange,
                          count: cemetery.reservedSpaces,
                          label: 'бронь',
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(
                          color: Colors.grey,
                          count: cemetery.occupiedSpaces,
                          label: 'занято',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.iconAndText,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Color color;
  final int count;
  final String label;

  const _StatusChip({
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          color: color.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
