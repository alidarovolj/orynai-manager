import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/auth_state_manager.dart';
import '../services/api_service.dart';

enum _ProfileSection { personalData, burialRequests, appeals }

enum _ContentView { list, create }

class ManagerProfilePage extends StatefulWidget {
  const ManagerProfilePage({super.key});

  @override
  State<ManagerProfilePage> createState() => _ManagerProfilePageState();
}

class _ManagerProfilePageState extends State<ManagerProfilePage> {
  _ProfileSection _section = _ProfileSection.personalData;
  final _auth = AuthStateManager();
  final _api = ApiService();

  // Burial requests state
  List<Map<String, dynamic>> _requests = [];
  bool _loadingRequests = false;
  String? _requestsError;
  Map<String, dynamic>? _selectedRequest;
  _ContentView _requestsView = _ContentView.list;

  // Appeals state
  List<Map<String, dynamic>> _appeals = [];
  bool _loadingAppeals = false;
  String? _appealsError;
  _ContentView _appealsView = _ContentView.list;

  // Cemeteries for forms
  List<Map<String, dynamic>> _cemeteries = [];

  @override
  void initState() {
    super.initState();
    _loadBurialRequests();
    _loadAppeals();
  }

  // ─── API Loaders ───────────────────────────────────────────────────────────

  Future<void> _loadBurialRequests() async {
    if (_loadingRequests) return;
    setState(() { _loadingRequests = true; _requestsError = null; });
    try {
      final phone = _auth.currentUser?.phone ?? '';
      final resp = await _api.getBurialRequests(userPhone: phone);
      final list = _extractList(resp);
      if (mounted) setState(() { _requests = list; _loadingRequests = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingRequests = false; _requestsError = 'Не удалось загрузить заявки. Проверьте подключение.'; });
    }
  }

  Future<void> _loadAppeals() async {
    if (_loadingAppeals) return;
    setState(() { _loadingAppeals = true; _appealsError = null; });
    try {
      final resp = await _api.get('/api/v3/rip-government/v1/appeal/my', requiresAuth: true);
      final list = _extractList(resp);
      if (mounted) setState(() { _appeals = list; _loadingAppeals = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingAppeals = false; _appealsError = 'Не удалось загрузить обращения.'; });
    }
  }

  Future<void> _loadCemeteries() async {
    if (_cemeteries.isNotEmpty) return;
    try {
      final resp = await _api.get('/api/v1/cemeteries');
      final list = _extractList(resp);
      if (mounted) setState(() => _cemeteries = list);
    } catch (_) {}
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

  void _selectSection(_ProfileSection s) {
    setState(() {
      _section = s;
      _selectedRequest = null;
      _requestsView = _ContentView.list;
      _appealsView = _ContentView.list;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayName = _auth.getDisplayName();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.iconAndText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/logos/main.png', height: 30,
                errorBuilder: (_, __, ___) => const SizedBox(width: 30)),
            const SizedBox(width: 8),
            const Text('Кабинет Менеджера',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.iconAndText)),
          ],
        ),
        actions: [
          if (displayName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.iconAndText, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(displayName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.iconAndText)),
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
          _navItem('Личные данные', _ProfileSection.personalData, Icons.person_outline),
          const SizedBox(height: 4),
          _navItem('Заявки на захоронение', _ProfileSection.burialRequests, Icons.assignment_outlined),
          const SizedBox(height: 4),
          _navItem('Обращения в администрацию', _ProfileSection.appeals, Icons.mail_outline),
        ],
      ),
    );
  }

  Widget _navItem(String title, _ProfileSection section, IconData icon) {
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
      case _ProfileSection.personalData:
        return _buildPersonalData();
      case _ProfileSection.burialRequests:
        return _buildBurialSection();
      case _ProfileSection.appeals:
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
        onSuccess: () {
          setState(() => _appealsView = _ContentView.list);
          _appeals.clear();
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
    if (_requestsView == _ContentView.create) {
      return _BurialRequestCreateForm(
        api: _api,
        cemeteries: _cemeteries,
        userPhone: _auth.currentUser?.phone ?? '',
        onLoadCemeteries: _loadCemeteries,
        onBack: () => setState(() => _requestsView = _ContentView.list),
        onSuccess: () {
          setState(() { _requestsView = _ContentView.list; _selectedRequest = null; });
          _requests.clear();
          _loadBurialRequests();
        },
      );
    }

    if (_loadingRequests && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.buttonBackground));
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (_selectedRequest != null) {
        final listW = (constraints.maxWidth * 0.42).clamp(260.0, 400.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: listW, child: _buildRequestsList()),
            const VerticalDivider(width: 1),
            Expanded(child: _RequestDetailPanel(
              request: _selectedRequest!,
              onClose: () => setState(() => _selectedRequest = null),
            )),
          ],
        );
      }
      return _buildRequestsList();
    });
  }

  Widget _buildRequestsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          title: 'Заявки на захоронение',
          isLoading: _loadingRequests,
          onRefresh: _loadBurialRequests,
          onAdd: () {
            _loadCemeteries();
            setState(() { _requestsView = _ContentView.create; _selectedRequest = null; });
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
                isSelected: _selectedRequest != null && _selectedRequest!['id'] == _requests[i]['id'],
                onTap: () => setState(() => _selectedRequest = _requests[i]),
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
    required VoidCallback onRefresh,
    required VoidCallback onAdd,
    required String addLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.iconAndText)),
          ),
          if (isLoading)
            const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.buttonBackground))
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.iconAndText, size: 20),
              onPressed: onRefresh, tooltip: 'Обновить',
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
// Детальная панель заявки
// ─────────────────────────────────────────────────────────────────────────────

class _RequestDetailPanel extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onClose;
  const _RequestDetailPanel({required this.request, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cemetery = request['cemetery_name']?.toString() ?? '—';
    final sector = request['sector_number']?.toString() ?? '—';
    final row = request['row_number']?.toString() ?? '—';
    final graveNum = request['grave_number']?.toString() ?? '—';
    final deceased = request['deceased'] as Map<String, dynamic>?;
    final fullName = deceased?['full_name']?.toString() ?? '—';
    final deathDate = deceased?['death_date']?.toString();
    final birthDate = deceased?['birth_date']?.toString();
    final burialDate = request['burial_date']?.toString();
    final burialTime = request['burial_time']?.toString();
    final status = request['status']?.toString() ?? '';
    final id = request['id']?.toString() ?? '';
    final requestNumber = request['request_number']?.toString() ?? 'ЗАХ-${id.padLeft(3, '0')}';
    final photosUrls = request['photos_urls'];
    final List<String> photos = photosUrls is List ? photosUrls.map((e) => e.toString()).toList() : [];

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close, color: AppColors.iconAndText), onPressed: onClose),
            Expanded(child: Text(requestNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.iconAndText))),
            _StatusBadge(status: status),
            const SizedBox(width: 8),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (photos.isNotEmpty) ...[
                SizedBox(
                  height: 180,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(photos[i], width: 240, height: 180, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 240, height: 180, color: Colors.grey.shade200,
                              child: const Icon(Icons.image_not_supported, color: Colors.grey))),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Container(height: 140, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey.shade400))),
                const SizedBox(height: 20),
              ],
              _detailSection('Место захоронения', [
                _detailRow('Кладбище', cemetery),
                _detailRow('Сектор', sector),
                _detailRow('Ряд', row),
                _detailRow('Место', graveNum, isLast: true),
              ]),
              const SizedBox(height: 20),
              _detailSection('Данные умершего', [
                _detailRow('ФИО', fullName),
                if (birthDate != null) _detailRow('Дата рождения', _fmtDate(birthDate)),
                if (deathDate != null) _detailRow('Дата смерти', _fmtDate(deathDate), isLast: burialDate == null),
                if (burialDate != null)
                  _detailRow('Дата захоронения',
                      burialTime != null ? '${_fmtDate(burialDate)}, $burialTime' : _fmtDate(burialDate),
                      isLast: true),
              ]),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _detailSection(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.iconAndText)),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF4F0E7), borderRadius: BorderRadius.circular(12)),
          child: Column(children: rows)),
    ],
  );

  Widget _detailRow(String label, String value, {bool isLast = false}) => Column(
    children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.iconAndText.withValues(alpha: 0.6)))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.iconAndText))),
          ])),
      if (!isLast) Divider(height: 1, color: Colors.grey.shade300),
    ],
  );

  String _fmtDate(String iso) {
    try { final dt = DateTime.parse(iso); return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; }
    catch (_) { return iso; }
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
