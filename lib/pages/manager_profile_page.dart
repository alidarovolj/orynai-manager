import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/auth_state_manager.dart';
import '../services/api_service.dart';
import '../widgets/orynai_app_bar.dart';

enum ProfileSection { personalData, burialRequests, appeals }

enum _ContentView { list, create }

class ManagerProfilePage extends StatefulWidget {
  final ProfileSection initialSection;
  const ManagerProfilePage({
    super.key,
    this.initialSection = ProfileSection.personalData,
  });

  @override
  State<ManagerProfilePage> createState() => _ManagerProfilePageState();
}

class _ManagerProfilePageState extends State<ManagerProfilePage> {
  late ProfileSection _section;
  final _auth = AuthStateManager();
  final _api = ApiService();

  // Burial requests state
  List<Map<String, dynamic>> _requests = [];
  bool _loadingRequests = false;
  String? _requestsError;
  // _requestsView removed — create navigates to home

  // Appeals state
  List<Map<String, dynamic>> _appeals = [];
  bool _loadingAppeals = false;
  String? _appealsError;
  _ContentView _appealsView = _ContentView.list;


  static const _prefKeyRequests = 'profile_burial_requests_cache';
  static const _prefKeyAppeals = 'profile_appeals_cache';

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _restoreCacheAndFetch();
  }

  // ─── Cache helpers ─────────────────────────────────────────────────────────

  Future<void> _restoreCacheAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final rawReq = prefs.getString(_prefKeyRequests);
    final rawApp = prefs.getString(_prefKeyAppeals);

    // Показываем кэш мгновенно, если есть
    if (mounted && rawReq != null) {
      try {
        final cached = (json.decode(rawReq) as List).cast<Map<String, dynamic>>();
        setState(() => _requests = cached);
      } catch (_) {}
    }
    if (mounted && rawApp != null) {
      try {
        final cached = (json.decode(rawApp) as List).cast<Map<String, dynamic>>();
        setState(() => _appeals = cached);
      } catch (_) {}
    }

    // Затем обновляем в фоне
    _loadBurialRequests();
    _loadAppeals();
  }

  Future<void> _saveToCache(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json.encode(list));
    } catch (_) {}
  }

  // ─── API Loaders ───────────────────────────────────────────────────────────

  Future<void> _loadBurialRequests() async {
    if (_loadingRequests) return;
    setState(() { _loadingRequests = true; _requestsError = null; });
    try {
      final phone = _auth.currentUser?.phone ?? '';
      final resp = await _api.getBurialRequests(userPhone: phone);
      final list = _extractList(resp);
      if (mounted) {
        setState(() { _requests = list; _loadingRequests = false; });
        _saveToCache(_prefKeyRequests, list);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRequests = false;
          // Не затираем ошибкой если есть кэш
          if (_requests.isEmpty) _requestsError = 'Не удалось загрузить заявки. Проверьте подключение.';
        });
      }
    }
  }

  Future<void> _loadAppeals() async {
    if (_loadingAppeals) return;
    setState(() { _loadingAppeals = true; _appealsError = null; });
    try {
      final resp = await _api.get('/api/v3/rip-government/v1/appeal/my', requiresAuth: true);
      final list = _extractList(resp);
      if (mounted) {
        setState(() { _appeals = list; _loadingAppeals = false; });
        _saveToCache(_prefKeyAppeals, list);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAppeals = false;
          if (_appeals.isEmpty) _appealsError = 'Не удалось загрузить обращения.';
        });
      }
    }
  }


  List<Map<String, dynamic>> _extractList(dynamic resp) {
    if (resp == null) return [];
    if (resp is List) return resp.cast<Map<String, dynamic>>();
    if (resp is Map) {
      final d1 = resp['data'];
      if (d1 is List) return d1.cast<Map<String, dynamic>>();
      if (d1 is Map) {
        final d2 = d1['data'];
        if (d2 is List) return d2.cast<Map<String, dynamic>>();
        if (d2 is Map) {
          final d3 = d2['data'];
          if (d3 is List) return d3.cast<Map<String, dynamic>>();
        }
      }
    }
    return [];
  }

  void _selectSection(ProfileSection s) {
    setState(() {
      _section = s;
      _appealsView = _ContentView.list;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayName = _auth.getDisplayName();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: OrynaiAppBar(
        title: 'Кабинет менеджера',
        showLogo: true,
        showBack: true,
        actions: [
          if (displayName.isNotEmpty)
            Padding(
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
                      displayName,
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
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ─── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('КАБИНЕТ\nМЕНЕДЖЕРА\nКЛАДБИЩА',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.iconAndText, height: 1.2)),
          const SizedBox(height: 20),
          _navItem('Личные данные', ProfileSection.personalData, Icons.person_outline),
          const SizedBox(height: 4),
          _navItem('Заявки на захоронение', ProfileSection.burialRequests, Icons.assignment_outlined),
          const SizedBox(height: 4),
          _navItem('Обращения в администрацию', ProfileSection.appeals, Icons.mail_outline),
        ],
      ),
    );
  }

  Widget _navItem(String title, ProfileSection section, IconData icon) {
    final active = _section == section;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectSection(section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppColors.buttonBackground.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20,
                color: active ? AppColors.buttonBackground : AppColors.iconAndText.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? AppColors.iconAndText : AppColors.iconAndText.withValues(alpha: 0.85))),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Content Router ────────────────────────────────────────────────────────

  Widget _buildContent() {
    switch (_section) {
      case ProfileSection.personalData:
        return _buildPersonalData();
      case ProfileSection.burialRequests:
        return _buildBurialSection();
      case ProfileSection.appeals:
        return _buildAppealsSection();
    }
  }

  // ─── Личные данные ─────────────────────────────────────────────────────────

  Widget _buildPersonalData() {
    final user = _auth.currentUser;
    final fullName = [user?.surname ?? '', user?.name ?? '', user?.patronymic ?? '']
        .where((s) => s.isNotEmpty).join(' ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Личные данные',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.iconAndText)),
          const SizedBox(height: 20),
          _infoCard([
            _profileRow('ФИО', fullName.isNotEmpty ? fullName : '—'),
            _profileRow('ИИН', user?.iin?.isNotEmpty == true ? user!.iin! : '—'),
            _profileRow('Телефон', _formatPhone(user?.phone ?? '')),
          ]),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.iconAndText.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: children),
    );
  }

  Widget _profileRow(String label, String value) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              SizedBox(width: 160,
                  child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.iconAndText.withValues(alpha: 0.6)))),
              Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 16, color: AppColors.iconAndText, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
      ],
    );
  }

  // ─── Обращения ─────────────────────────────────────────────────────────────

  Widget _buildAppealsSection() {
    if (_appealsView == _ContentView.create) {
      return _AppealCreateForm(
        api: _api,
        userPhone: _auth.currentUser?.phone ?? '',
        onBack: () => setState(() => _appealsView = _ContentView.list),
        onSuccess: () async {
          setState(() { _appealsView = _ContentView.list; _appeals.clear(); });
          // Инвалидируем кэш перед обновлением
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_prefKeyAppeals);
          _loadAppeals();
        },
      );
    }
    return _buildAppealsList();
  }

  Widget _buildAppealsList() {
    if (_loadingAppeals && _appeals.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.buttonBackground));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          title: 'Обращения в администрацию',
          isLoading: _loadingAppeals,
          hasCachedData: _appeals.isNotEmpty,
          onRefresh: _loadAppeals,
          onAdd: () => setState(() => _appealsView = _ContentView.create),
          addLabel: 'Создать обращение',
        ),
        if (_appealsError != null && _appeals.isEmpty)
          _errorState(_appealsError!, _loadAppeals)
        else if (_appeals.isEmpty && !_loadingAppeals)
          _emptyState('Обращения не найдены', 'Нажмите «Создать обращение», чтобы отправить запрос')
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _appeals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AppealCard(appeal: _appeals[i]),
            ),
          ),
      ],
    );
  }

  // ─── Заявки на захоронение ─────────────────────────────────────────────────

  Widget _buildBurialSection() {
    if (_loadingRequests && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.buttonBackground));
    }
    return _buildRequestsList();
  }

  void _openRequestDetail(Map<String, dynamic> request) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestDetailSheet(request: request),
    );
  }

  Widget _buildRequestsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          title: 'Заявки на захоронение',
          isLoading: _loadingRequests,
          hasCachedData: _requests.isNotEmpty,
          onRefresh: _loadBurialRequests,
          onAdd: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          addLabel: 'Создать заявку',
        ),
        if (_requestsError != null && _requests.isEmpty)
          _errorState(_requestsError!, _loadBurialRequests)
        else if (_requests.isEmpty && !_loadingRequests)
          _emptyState('Заявки не найдены', 'Нажмите «Создать заявку» для подачи новой заявки')
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _RequestCard(
                request: _requests[i],
                isSelected: false,
                onTap: () => _openRequestDetail(_requests[i]),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Reusable Section UI ───────────────────────────────────────────────────

  Widget _sectionHeader({
    required String title,
    required bool isLoading,
    required bool hasCachedData,
    required VoidCallback onRefresh,
    required VoidCallback onAdd,
    required String addLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.iconAndText)),
              ),
              if (isLoading)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.buttonBackground))
              else
                SizedBox(
                  width: 36, height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.refresh, color: AppColors.iconAndText, size: 20),
                    onPressed: onRefresh, tooltip: 'Обновить',
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.buttonBackground,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(addLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (isLoading && hasCachedData)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.buttonBackground)),
                const SizedBox(width: 8),
                Text('Обновление данных...', style: TextStyle(fontSize: 12, color: AppColors.iconAndText.withValues(alpha: 0.6))),
              ],
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }

  Widget _errorState(String msg, VoidCallback retry) {
    return Expanded(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, size: 48, color: AppColors.iconAndText),
          const SizedBox(height: 16),
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: retry,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonBackground, foregroundColor: Colors.white),
            child: const Text('Повторить'),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Expanded(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 56, color: AppColors.iconAndText.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.iconAndText)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.iconAndText.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  // ─── Utils ─────────────────────────────────────────────────────────────────

  String _formatPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '+${d[0]} (${d.substring(1, 4)}) ${d.substring(4, 7)} ${d.substring(7, 9)} ${d.substring(9, 11)}';
    }
    return phone;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Карточка заявки на захоронение
// ─────────────────────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool isSelected;
  final VoidCallback onTap;
  const _RequestCard({required this.request, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = request['id']?.toString() ?? '';
    final requestNumber = request['request_number']?.toString() ??
        'ЗАХОРОНЕНИЕ: ${id.padLeft(3, '0')}';
    final cemetery = request['cemetery_name']?.toString() ?? '';
    final sector = request['sector_number']?.toString() ?? '';
    final row = request['row_number']?.toString() ?? '';
    final graveNum = request['grave_number']?.toString() ?? '';
    final status = request['status']?.toString() ?? '';
    final deceased = request['deceased'] as Map<String, dynamic>?;
    final fullName = deceased?['full_name']?.toString() ?? '—';
    final createdAt = request['created_at']?.toString() ?? request['createdAt']?.toString();
    final updatedAt = request['updated_at']?.toString() ?? request['updatedAt']?.toString();

    return Material(
      color: isSelected ? AppColors.buttonBackground.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.buttonBackground : Colors.transparent, width: isSelected ? 2 : 0),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(requestNumber.toUpperCase(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.iconAndText))),
                _StatusBadge(status: status),
              ]),
              const SizedBox(height: 8),
              if (createdAt != null) _infoLine('Создано', _fmtDateTime(createdAt)),
              if (updatedAt != null) _infoLine('Обновлено', _fmtDateTime(updatedAt)),
              const SizedBox(height: 6),
              _infoLine('Заявитель', fullName),
              if (cemetery.isNotEmpty || sector.isNotEmpty || graveNum.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (cemetery.isNotEmpty) _chip(cemetery),
                  if (sector.isNotEmpty) _chip('Сектор $sector'),
                  if (row.isNotEmpty) _chip('Ряд $row'),
                  if (graveNum.isNotEmpty) _chip('Место $graveNum'),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label: ', style: TextStyle(fontSize: 12, color: AppColors.iconAndText.withValues(alpha: 0.6))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.iconAndText))),
    ]),
  );

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFFE9EDED), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
  );

  String _fmtDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet — детали заявки
// ─────────────────────────────────────────────────────────────────────────────

class _RequestDetailSheet extends StatelessWidget {
  final Map<String, dynamic> request;
  const _RequestDetailSheet({required this.request});

  @override
  Widget build(BuildContext context) {
    final cemetery   = request['cemetery_name']?.toString() ?? '—';
    final sector     = request['sector_number']?.toString() ?? '—';
    final row        = request['row_number']?.toString() ?? '—';
    final graveNum   = request['grave_number']?.toString() ?? '—';
    final deceased   = request['deceased'] as Map<String, dynamic>?;
    final fullName   = deceased?['full_name']?.toString() ?? '—';
    final inn        = deceased?['inn']?.toString();
    final deathDate  = deceased?['death_date']?.toString();
    final birthDate  = deceased?['birth_date']?.toString();
    final burialDate = request['burial_date']?.toString();
    final burialTime = request['burial_time']?.toString();
    final expiresAt  = request['reservation_expires_at']?.toString();
    final status     = request['status']?.toString() ?? '';
    final id         = request['id']?.toString() ?? '';
    final requestNumber = request['request_number']?.toString() ?? 'ЗАХ-${id.padLeft(3, '0')}';
    final photosUrls = request['photos_urls'];
    final List<String> photos = photosUrls is List
        ? photosUrls.map((e) => e.toString()).toList()
        : [];

    final maxH = MediaQuery.of(context).size.height * 0.85;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Ручка
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFDDDDDD),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Шапка
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(requestNumber,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: AppColors.iconAndText)),
                const SizedBox(height: 4),
                _StatusBadge(status: status),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.iconAndText),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
        // Контент
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Фото
              if (photos.isNotEmpty) ...[
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(photos[i], width: 220, height: 160, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 220, height: 160, color: Colors.grey.shade100,
                              child: const Icon(Icons.image_not_supported, color: Colors.grey))),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              // Место захоронения
              _section('Место захоронения', [
                _row('Кладбище', cemetery),
                _row('Сектор', sector),
                _row('Ряд', row),
                _row('Место', graveNum, isLast: true),
              ]),
              const SizedBox(height: 16),
              // Данные умершего
              _section('Данные умершего', [
                _row('ФИО', fullName),
                if (inn != null && inn.isNotEmpty) _row('ИИН', inn),
                if (birthDate != null) _row('Дата рождения', _fmt(birthDate)),
                if (deathDate != null)
                  _row('Дата смерти', _fmt(deathDate), isLast: burialDate == null),
                if (burialDate != null)
                  _row('Дата захоронения',
                      burialTime != null && burialTime.isNotEmpty
                          ? '${_fmt(burialDate)}, $burialTime'
                          : _fmt(burialDate),
                      isLast: true),
              ]),
              if (expiresAt != null && expiresAt.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF8D6E00)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Бронь действует до ${_fmt(expiresAt)}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF8D6E00),
                              fontWeight: FontWeight.w500)),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _section(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: AppColors.iconAndText)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F0E7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: rows),
      ),
    ],
  );

  Widget _row(String label, String value, {bool isLast = false}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          SizedBox(width: 130,
              child: Text(label, style: TextStyle(fontSize: 13,
                  color: AppColors.iconAndText.withValues(alpha: 0.55)))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: AppColors.iconAndText))),
        ]),
      ),
      if (!isLast) Divider(height: 1, color: Colors.grey.shade200),
    ],
  );

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) { return iso; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Карточка обращения
// ─────────────────────────────────────────────────────────────────────────────

class _AppealCard extends StatelessWidget {
  final Map<String, dynamic> appeal;
  const _AppealCard({required this.appeal});

  @override
  Widget build(BuildContext context) {
    final id = appeal['id']?.toString() ?? '';
    final type = appeal['type'] as Map<String, dynamic>?;
    final typeName = type?['nameRu']?.toString() ?? type?['name']?.toString() ?? '—';
    final content = appeal['content']?.toString() ?? '—';
    final status = appeal['status'];
    final statusStr = status is Map
        ? (status['nameRu'] ?? status['value'] ?? status['name'] ?? '').toString()
        : (status ?? '').toString();
    final createdAt = appeal['created_at']?.toString() ?? appeal['createdAt']?.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.iconAndText.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Обращение №${id.padLeft(5, '0')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.iconAndText))),
          _AppealStatusBadge(status: statusStr),
        ]),
        const SizedBox(height: 8),
        if (typeName != '—') ...[
          Text('Тип: $typeName', style: TextStyle(fontSize: 13, color: AppColors.iconAndText.withValues(alpha: 0.7))),
          const SizedBox(height: 6),
        ],
        Text(content, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: AppColors.iconAndText)),
        if (createdAt != null) ...[
          const SizedBox(height: 8),
          Text(_fmtDate(createdAt), style: TextStyle(fontSize: 12, color: AppColors.iconAndText.withValues(alpha: 0.6))),
        ],
      ]),
    );
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Форма создания обращения
// ─────────────────────────────────────────────────────────────────────────────

class _AppealCreateForm extends StatefulWidget {
  final ApiService api;
  final String userPhone;
  final VoidCallback onBack;
  final VoidCallback onSuccess;
  const _AppealCreateForm({required this.api, required this.userPhone, required this.onBack, required this.onSuccess});

  @override
  State<_AppealCreateForm> createState() => _AppealCreateFormState();
}

class _AppealCreateFormState extends State<_AppealCreateForm> {
  final _contentCtrl = TextEditingController();
  int? _selectedTypeId;
  bool _loading = false;
  String? _error;

  static const int _maxLen = 3500;
  static const List<Map<String, dynamic>> _appealTypes = [
    {'id': 1, 'value': 'COMPLAINT', 'nameRu': 'Жалоба'},
    {'id': 2, 'value': 'OFFER', 'nameRu': 'Предложение'},
    {'id': 3, 'value': 'REQUEST_FOR_INFO', 'nameRu': 'Запрос информации'},
  ];

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedTypeId == null) { setState(() => _error = 'Выберите тип обращения.'); return; }
    if (_contentCtrl.text.trim().isEmpty) { setState(() => _error = 'Введите текст обращения.'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.put(
        '/api/v3/rip-government/v1/appeal',
        body: {
          'userPhone': widget.userPhone,
          'typeId': _selectedTypeId,
          'content': _contentCtrl.text.trim(),
          'akimatId': 6,
        },
        requiresAuth: true,
      );
      if (mounted) widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Не удалось отправить обращение. Попробуйте позже.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.iconAndText), onPressed: widget.onBack),
          const SizedBox(width: 4),
          const Text('Создать обращение',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.iconAndText)),
        ]),
        const SizedBox(height: 24),
        _fieldLabel('Тип обращения'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: _selectedTypeId,
              hint: Text('Выберите тип обращения', style: TextStyle(color: AppColors.iconAndText.withValues(alpha: 0.5))),
              items: _appealTypes.map((t) => DropdownMenuItem<int>(
                value: t['id'] as int,
                child: Text(t['nameRu'] as String),
              )).toList(),
              onChanged: (v) => setState(() => _selectedTypeId = v),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _fieldLabel('Текст обращения'),
        const SizedBox(height: 8),
        Stack(children: [
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            maxLength: _maxLen,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Опишите вашу проблему, предложение или запрос...',
              hintStyle: TextStyle(color: AppColors.iconAndText.withValues(alpha: 0.4)),
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.buttonBackground, width: 1.5)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          Positioned(right: 10, bottom: 8,
              child: Text('${_contentCtrl.text.length}/$_maxLen',
                  style: TextStyle(fontSize: 12, color: AppColors.iconAndText.withValues(alpha: 0.5)))),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
          ),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.iconAndText,
                side: BorderSide(color: Colors.grey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: (_loading || _selectedTypeId == null || _contentCtrl.text.trim().isEmpty) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.buttonBackground,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Отправить', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _fieldLabel(String text) => Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.iconAndText));
}

// ─────────────────────────────────────────────────────────────────────────────
// Форма создания заявки на захоронение (перенос)
// ─────────────────────────────────────────────────────────────────────────────

class _BurialRequestCreateForm extends StatefulWidget {
  final ApiService api;
  final List<Map<String, dynamic>> cemeteries;
  final String userPhone;
  final Future<void> Function() onLoadCemeteries;
  final VoidCallback onBack;
  final VoidCallback onSuccess;

  const _BurialRequestCreateForm({
    required this.api,
    required this.cemeteries,
    required this.userPhone,
    required this.onLoadCemeteries,
    required this.onBack,
    required this.onSuccess,
  });

  @override
  State<_BurialRequestCreateForm> createState() => _BurialRequestCreateFormState();
}

class _BurialRequestCreateFormState extends State<_BurialRequestCreateForm> {
  final _reasonCtrl = TextEditingController();
  final _foreignCtrl = TextEditingController();
  int? _fromId;
  int? _toId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.onLoadCemeteries();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _foreignCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _fromId != null && _toId != null && _reasonCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_isValid) { setState(() => _error = 'Заполните все обязательные поля.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.put(
        '/api/v3/rip-government/v1/request',
        body: {
          'userPhone': widget.userPhone,
          'fromBurialId': _fromId,
          'toBurialId': _toId,
          'reason': _reasonCtrl.text.trim(),
          'foreign_cemetry': _foreignCtrl.text.trim(),
          'akimatId': 6,
        },
        requiresAuth: true,
      );
      if (mounted) widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Не удалось создать заявку. Попробуйте позже.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cemOptions = widget.cemeteries.isNotEmpty ? widget.cemeteries : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.iconAndText), onPressed: widget.onBack),
          const SizedBox(width: 4),
          const Text('Создать заявку на захоронение',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.iconAndText)),
        ]),
        const SizedBox(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fieldLabel('Откуда (текущее кладбище) *'),
            const SizedBox(height: 8),
            _cemeteryDropdown('Выберите кладбище', _fromId, cemOptions, (v) => setState(() => _fromId = v)),
          ])),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fieldLabel('Куда (новое кладбище) *'),
            const SizedBox(height: 8),
            _cemeteryDropdown('Выберите кладбище', _toId, cemOptions, (v) => setState(() => _toId = v)),
          ])),
        ]),
        const SizedBox(height: 20),
        _fieldLabel('Причина переноса *'),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonCtrl,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Опишите причину переноса захоронения'),
        ),
        const SizedBox(height: 20),
        _fieldLabel('Иностранное кладбище (если применимо)'),
        const SizedBox(height: 8),
        TextField(
          controller: _foreignCtrl,
          decoration: _inputDecoration('Название иностранного кладбища'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
          ),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.iconAndText,
                side: BorderSide(color: Colors.grey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: (_loading || !_isValid) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.buttonBackground,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Создать заявку', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _cemeteryDropdown(String hint, int? value, List<Map<String, dynamic>> options, ValueChanged<int?> onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          hint: Text(hint, style: TextStyle(color: AppColors.iconAndText.withValues(alpha: 0.5))),
          items: options.map((c) => DropdownMenuItem<int>(
            value: (c['id'] is int) ? c['id'] as int : int.tryParse(c['id'].toString()),
            child: Text(c['name']?.toString() ?? '—', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.iconAndText.withValues(alpha: 0.4)),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.buttonBackground, width: 1.5)),
    contentPadding: const EdgeInsets.all(14),
  );

  Widget _fieldLabel(String text) => Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.iconAndText));
}

// ─────────────────────────────────────────────────────────────────────────────
// Бейдж статуса заявки на захоронение
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _info(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  (String, Color) _info(String s) {
    switch (s.toLowerCase()) {
      case 'pending':    return ('Ожидание', const Color(0xFFD97706));
      case 'paid':       return ('Оплачено', const Color(0xFF1EB676));
      case 'confirmed':  return ('Подтверждено', const Color(0xFF059669));
      case 'cancelled':  return ('Отменено', const Color(0xFFDC2626));
      case 'reserved':   return ('Резервирован', const Color(0xFFD97706));
      case 'occupied':   return ('Захоронен', Colors.grey);
      default:           return (s.isNotEmpty ? s : '—', const Color(0xFF6B7280));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Бейдж статуса обращения
// ─────────────────────────────────────────────────────────────────────────────

class _AppealStatusBadge extends StatelessWidget {
  final String status;
  const _AppealStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _info(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: fg)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  (String, Color, Color) _info(String s) {
    final v = s.toUpperCase();
    if (v.contains('REJECT') || v.contains('ОТКАЗ')) return ('Отказано', const Color(0xFFFDECEC), const Color(0xFFB42318));
    if (v.contains('CONFIRM') || v.contains('ПОДТВЕР')) return ('Подтверждено', const Color(0xFFEAF7ED), const Color(0xFF2E7D32));
    if (v.contains('CLOSED') || v.contains('ЗАКРЫТО')) return ('Закрыто', const Color(0xFFEAF7ED), const Color(0xFF2E7D32));
    if (v.contains('IN_PROCESS') || v.contains('В РАБОТЕ')) return ('В работе', const Color(0xFFFFF7E6), const Color(0xFFA56700));
    if (v.contains('NEW') || v.contains('НОВЫЙ')) return ('Новый', const Color(0xFFFFF7E6), const Color(0xFFA56700));
    if (v.contains('PENDING') || v.contains('ОЖИДАН')) return ('Ожидание', const Color(0xFFFFF7E6), const Color(0xFFA56700));
    return (s.isNotEmpty ? s : '—', const Color(0xFFEEF2F7), const Color(0xFF374151));
  }
}
