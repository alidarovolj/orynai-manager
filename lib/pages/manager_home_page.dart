import 'dart:math' show min, sin, cos, sqrt, atan2, pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';
import '../widgets/orynai_app_bar.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/api_service.dart';
import '../services/cemetery_service.dart';
import '../services/auth_state_manager.dart';
import '../services/location_service.dart';
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
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  // GPS для расчёта расстояния до кладбищ
  double? _userLat, _userLon;

  // Фильтр по религии (null = все)
  String? _selectedReligion;

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
    _checkAuth();
    _fetchUserLocation();
  }

  /// Запрос текущего пользователя — проверяет, что токен ещё действителен.
  /// При 401 ApiService автоматически редиректит на страницу входа.
  Future<void> _checkAuth() async {
    try {
      await _apiService.getCurrentUser();
    } catch (_) {
      // Ошибки сети/сервера игнорируем — 401 обрабатывается в ApiService
    }
  }

  Future<void> _fetchUserLocation() async {
    final pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
      });
    }
  }

  // ─── Фильтр и расстояния ────────────────────────────────────────────────────

  List<String> get _religionOptions {
    final set = <String>{};
    for (final c in _cemeteries) {
      if (c.religion.isNotEmpty) set.add(c.religion);
    }
    return set.toList()..sort();
  }

  List<Cemetery> get _filteredCemeteries {
    if (_selectedReligion == null || _selectedReligion!.isEmpty) {
      return _cemeteries;
    }
    return _cemeteries.where((c) => c.religion == _selectedReligion).toList();
  }

  double? _distanceTo(Cemetery c) {
    if (_userLat == null || _userLon == null) return null;
    if (c.locationCoords.length < 2) return null;
    return _haversineKm(_userLat!, _userLon!, c.locationCoords[0], c.locationCoords[1]);
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _religionLabel(String r) {
    switch (r) {
      case 'Ислам': return 'Мусульманское кладбище';
      case 'Христианство': return 'Христианское кладбище';
      default: return r.isNotEmpty ? r : 'Кладбище';
    }
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

  static String _shortName(String full) {
    if (full.isEmpty) return 'Менеджер';
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0]} ${parts[1][0].toUpperCase()}.';
    return parts[0];
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _authManager.getDisplayName();
    final short = _shortName(displayName);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: OrynaiAppBar(
        title: 'Кабинет менеджера',
        showLogo: true,
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
              icon: const Icon(Icons.sync, color: AppColors.iconAndText, size: 20),
              tooltip: 'Синхронизировать',
              onPressed: _syncNow,
            ),
          const SizedBox(width: 4),
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
            offset: const Offset(0, 48),
            child: Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDDDDDD), width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: AppColors.iconAndText),
                    const SizedBox(width: 6),
                    Text(
                      short,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.iconAndText,
                      ),
                    ),
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
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(
          //     AppSizes.paddingMedium,
          //     AppSizes.paddingMedium,
          //     AppSizes.paddingMedium,
          //     8,
          //   ),
          //   child: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       const Text(
          //         'Кладбища',
          //         style: TextStyle(
          //           fontSize: 24,
          //           fontWeight: FontWeight.w700,
          //           color: AppColors.iconAndText,
          //         ),
          //       ),
          //       const SizedBox(height: 4),
          //       Text(
          //         'Выберите кладбище для работы',
          //         style: TextStyle(
          //           fontSize: 14,
          //           color: AppColors.iconAndText.withValues(alpha: 0.7),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),

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

    // if (_cachedAt != null) {
    //   final diff = DateTime.now().difference(_cachedAt!);
    //   final label = diff.inMinutes < 1
    //       ? 'только что'
    //       : diff.inHours < 1
    //       ? '${diff.inMinutes} мин. назад'
    //       : diff.inDays < 1
    //       ? '${diff.inHours} ч. назад'
    //       : '${diff.inDays} д. назад';
    //   return Container(
    //     width: double.infinity,
    //     color: Colors.green.withValues(alpha: 0.06),
    //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    //     child: Text(
    //       'Данные обновлены $label',
    //       style: TextStyle(fontSize: 11, color: Colors.green.shade700),
    //     ),
    //   );
    // }

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
    final filtered = _filteredCemeteries;
    final city = _cemeteries.isNotEmpty ? _cemeteries.first.city : 'Алматы';
    final religions = _religionOptions;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: const Color(0x14000000)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Фиксированная шапка ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок
                const Text(
                  'ЗАБРОНИРОВАТЬ МЕСТО',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF201001),
                    letterSpacing: 0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 14),
                // Город
                Row(
                  children: [
                    const Text(
                      'Город:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.iconAndText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.location_on,
                      size: 18,
                      color: AppColors.buttonBackground,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      city,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.iconAndText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Дропдаун религии
                if (religions.isNotEmpty)
                  _ReligionDropdown(
                    religions: religions,
                    selected: _selectedReligion,
                    iconPath: _selectedReligion != null
                        ? _getReligionIconPath(Cemetery(
                            id: 0, name: '', description: '', country: '',
                            city: '', streetName: '', phone: '',
                            locationCoords: [], polygonCoordinates: [],
                            religion: _selectedReligion!, burialPrice: 0,
                            status: '', capacity: 0, freeSpaces: 0,
                            reservedSpaces: 0, occupiedSpaces: 0,
                          ))
                        : null,
                    onChanged: (val) => setState(() {
                      _selectedReligion = val;
                      _selectedCemetery = null;
                      _selectedGrave = null;
                    }),
                  ),
                const SizedBox(height: 12),
                // Счётчик результатов
                Text(
                  '${filtered.length} ${_pluralResults(filtered.length)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.iconAndText.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ─── Список кладбищ ───────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshCemeteries,
              color: AppColors.buttonBackground,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final cemetery = filtered[index];
                  final isCemSelected = cemetery.id == _selectedCemetery?.id;
                  // Место считается выбранным на этом кладбище
                  final graveHere = isCemSelected ? _selectedGrave : null;
                  return _CemeteryCard(
                    cemetery: cemetery,
                    iconPath: _getReligionIconPath(cemetery),
                    religionLabel: _religionLabel(cemetery.religion),
                    distance: _distanceTo(cemetery),
                    selected: isCemSelected,
                    selectedGrave: graveHere,
                    onTap: () => setState(() {
                      _selectedCemetery = isCemSelected && _selectedGrave == null
                          ? null
                          : cemetery;
                      _selectedGrave = null;
                    }),
                    onBook: graveHere != null && graveHere.isFree
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PlaceBookingPage(
                                  cemetery: cemetery,
                                  grave: graveHere,
                                ),
                              ),
                            )
                        : null,
                    onOpenCard: graveHere != null
                        ? () => Navigator.of(context)
                            .push(
                              MaterialPageRoute<void>(
                                builder: (_) => GraveDetailPage(
                                  cemetery: cemetery,
                                  grave: graveHere,
                                ),
                              ),
                            )
                            .then((_) => _loadCemeteries())
                        : null,
                    onCloseGrave: graveHere != null
                        ? () => setState(() => _selectedGrave = null)
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _pluralResults(int n) {
    if (n % 100 >= 11 && n % 100 <= 14) return 'результатов';
    switch (n % 10) {
      case 1: return 'результат';
      case 2: case 3: case 4: return 'результата';
      default: return 'результатов';
    }
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

class _CemeteryCard extends StatelessWidget {
  final Cemetery cemetery;
  final String iconPath;
  final String religionLabel;
  final double? distance;
  final bool selected;
  final Grave? selectedGrave;
  final VoidCallback onTap;
  final VoidCallback? onBook;
  final VoidCallback? onOpenCard;
  final VoidCallback? onCloseGrave;

  const _CemeteryCard({
    required this.cemetery,
    required this.iconPath,
    required this.religionLabel,
    required this.selected,
    required this.onTap,
    this.distance,
    this.selectedGrave,
    this.onBook,
    this.onOpenCard,
    this.onCloseGrave,
  });

  static String _fmtDist(double km) {
    if (km < 1) return '${(km * 1000).round()} м';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'free': return 'Свободно';
      case 'reserved': return 'Забронировано';
      case 'occupied': return 'Захоронено';
      default: return 'Резерв';
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'free': return const Color(0xFF4CAF50);
      case 'reserved': return Colors.orange;
      case 'occupied': return Colors.grey;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGrave = selectedGrave != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.buttonBackground.withValues(alpha: 0.08)
            : const Color(0xFFF4F0E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.buttonBackground : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Заголовок карточки ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      iconPath,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        AppColors.iconAndText,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (_) => const Icon(
                        Icons.place,
                        color: AppColors.iconAndText,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  cemetery.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.iconAndText,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (distance != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${_fmtDist(distance!)})',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.iconAndText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            religionLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.iconAndText.withValues(alpha: 0.6),
                            ),
                          ),
                          if (cemetery.streetName.isNotEmpty)
                            Text(
                              '${cemetery.streetName}, ${cemetery.city}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.iconAndText.withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      selected ? Icons.keyboard_arrow_down : Icons.chevron_right,
                      color: selected
                          ? AppColors.buttonBackground
                          : AppColors.iconAndText.withValues(alpha: 0.45),
                      size: 20,
                    ),
                  ],
                ),
              ),

              // ── Раскрытый блок (выбрано кладбище ИЛИ место) ───────────────
              if (selected) ...[
                Divider(
                  height: 1, thickness: 1, indent: 14, endIndent: 14,
                  color: AppColors.iconAndText.withValues(alpha: 0.1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Адрес
                      if (cemetery.streetName.isNotEmpty)
                        _DetailRow(
                          icon: Icons.location_on,
                          iconColor: AppColors.buttonBackground,
                          text: '${cemetery.streetName}, ${cemetery.city}',
                          trailing: distance != null
                              ? '(${_fmtDist(distance!)} от вас)'
                              : null,
                        ),
                      // Телефон
                      if (cemetery.phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DetailRow(
                          icon: Icons.phone,
                          iconColor: AppColors.iconAndText,
                          text: '+${cemetery.phone}',
                        ),
                      ],
                      // Описание
                      if (cemetery.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          cemetery.description.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.iconAndText.withValues(alpha: 0.7),
                          ),
                        ),
                      ],

                      // ── Блок выбранного места ──────────────────────────────
                      if (hasGrave) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.iconAndText.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Участок ${selectedGrave!.sectorNumber}  ·  '
                                      'Ряд ${selectedGrave!.rowNumber}  ·  '
                                      'Место ${selectedGrave!.graveNumber}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.iconAndText,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: onCloseGrave,
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: AppColors.iconAndText.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 9, height: 9,
                                    decoration: BoxDecoration(
                                      color: _statusColor(selectedGrave!.status),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    _statusLabel(selectedGrave!.status),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _statusColor(selectedGrave!.status),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Кнопка «Открыть карточку»
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: onOpenCard,
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text(
                              'Открыть карточку менеджера',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.iconAndText,
                              side: BorderSide(
                                color: AppColors.iconAndText.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        if (selectedGrave!.isFree) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: onBook,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text(
                                'Забронировать место',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.buttonBackground,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        // Нет выбранного места — подсказка
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.buttonBackground.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 16,
                                color: AppColors.buttonBackground,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Нажмите на место на карте для выбора',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.iconAndText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final String? trailing;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: text,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.iconAndText.withValues(alpha: 0.85),
                  ),
                ),
                if (trailing != null)
                  TextSpan(
                    text: '  $trailing',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.iconAndText.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReligionDropdown extends StatelessWidget {
  final List<String> religions;
  final String? selected;
  final String? iconPath;
  final ValueChanged<String?> onChanged;

  const _ReligionDropdown({
    required this.religions,
    required this.selected,
    required this.onChanged,
    this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x18000000)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.iconAndText,
            size: 22,
          ),
          hint: Row(
            children: [
              SvgPicture.asset(
                'assets/icons/religions/003-islam.svg',
                width: 22, height: 22,
                colorFilter: const ColorFilter.mode(
                  AppColors.iconAndText, BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Выбрать религию',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.iconAndText,
                ),
              ),
            ],
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Все религии',
                style: TextStyle(fontSize: 14, color: AppColors.iconAndText),
              ),
            ),
            ...religions.map(
              (r) => DropdownMenuItem<String?>(
                value: r,
                child: Text(
                  r,
                  style: const TextStyle(fontSize: 14, color: AppColors.iconAndText),
                ),
              ),
            ),
          ],
          selectedItemBuilder: (context) => [
            // «Все религии» — без иконки
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Все религии',
                style: TextStyle(fontSize: 14, color: AppColors.iconAndText),
              ),
            ),
            ...religions.map((r) {
              final icon = r == 'Ислам'
                  ? 'assets/icons/religions/003-islam.svg'
                  : 'assets/icons/religions/christianity.svg';
              return Row(
                children: [
                  SvgPicture.asset(
                    icon, width: 22, height: 22,
                    colorFilter: const ColorFilter.mode(
                      AppColors.iconAndText, BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    r,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.iconAndText,
                    ),
                  ),
                ],
              );
            }),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
