import 'dart:io' show File;
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../widgets/orynai_app_bar.dart';
import '../services/api_service.dart';
import '../services/auth_state_manager.dart';

class PlaceBookingPage extends StatefulWidget {
  final Cemetery cemetery;
  final Grave grave;

  const PlaceBookingPage({
    super.key,
    required this.cemetery,
    required this.grave,
  });

  @override
  State<PlaceBookingPage> createState() => _PlaceBookingPageState();
}

class _PlaceBookingPageState extends State<PlaceBookingPage> {
  final _api = ApiService();

  final _iinController       = TextEditingController();
  final _nameController      = TextEditingController();
  final _deathDateController = TextEditingController();
  final _certController      = TextEditingController(); // display-only
  final _burialDateController= TextEditingController();
  final _burialTimeController= TextEditingController();

  bool _datesEnabled    = false;
  bool _loadingIin      = false;
  bool _nameFromApi     = false;
  String? _lastIin;
  File? _certFile;

  bool _saving = false;
  String? _iinError;
  String? _nameError;

  static const int _bookingDays = 3;
  static const _labelColor = Color(0xFF201001);
  static const _valueColor  = Color(0xFF8A8580);
  static const _dividerColor= Color(0xFFE5E0D8);

  @override
  void initState() {
    super.initState();
    _iinController.addListener(_onIinChanged);
    _iinController.addListener(() => setState(() {}));
    _nameController.addListener(() => setState(() {}));
    _burialDateController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _iinController.dispose();
    _nameController.dispose();
    _deathDateController.dispose();
    _certController.dispose();
    _burialDateController.dispose();
    _burialTimeController.dispose();
    super.dispose();
  }

  // ─── ИИН → автозаполнение ─────────────────────────────────────────────────

  void _onIinChanged() {
    final iin = _iinController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (iin.length == 12 && iin != _lastIin) {
      _lastIin = iin;
      _searchByIin(iin);
    }
    // Сброс если ИИН изменили
    if (iin.length < 12 && _nameFromApi) {
      setState(() {
        _nameFromApi = false;
        _nameController.clear();
      });
    }
  }

  Future<void> _searchByIin(String iin) async {
    setState(() { _loadingIin = true; _iinError = null; });
    try {
      final resp = await _api.searchDeceasedByIin(iin);
      if (!mounted) return;

      if (resp['code'] == 'FDTH_COMPLETED' && resp['data'] != null) {
        final data    = resp['data'] as Map<String, dynamic>;
        final records = (data['actRecords'] as Map<String, dynamic>?)?['record'] as List?;
        if (records != null && records.isNotEmpty) {
          final person = (records[0] as Map<String, dynamic>)['person'] as Map<String, dynamic>?;
          if (person != null) {
            final parts = [
              person['surname']?.toString() ?? '',
              person['name']?.toString() ?? '',
              person['secondname']?.toString() ?? '',
            ].where((s) => s.isNotEmpty).toList();
            if (parts.isNotEmpty) {
              setState(() {
                _nameController.text = parts.join(' ');
                _nameFromApi = true;
              });
            }
          }
        }
      }
    } catch (_) {
      // Не блокируем — пользователь вводит ФИО вручную
    } finally {
      if (mounted) setState(() => _loadingIin = false);
    }
  }

  // ─── Дата смерти / похорон ──────────────────────────────────────────────────

  Future<void> _pickDeathDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
      builder: _datepickerTheme,
    );
    if (d != null && mounted) {
      _deathDateController.text = DateFormat('dd.MM.yyyy').format(d);
      setState(() {});
    }
  }

  Future<void> _pickBurialDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ru'),
      builder: _datepickerTheme,
    );
    if (d != null && mounted) {
      _burialDateController.text = DateFormat('dd.MM.yyyy').format(d);
      setState(() {});
    }
  }

  Future<void> _pickBurialTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: _datepickerTheme,
    );
    if (t != null && mounted) {
      _burialTimeController.text =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Widget _datepickerTheme(BuildContext ctx, Widget? child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.buttonBackground),
        ),
        child: child!,
      );

  // ─── Свидетельство о смерти ──────────────────────────────────────────────────

  Future<void> _pickCert() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _certFile = File(file.path));
  }

  void _removeCert() => setState(() => _certFile = null);

  // ─── Отправка ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final iin  = _iinController.text.replaceAll(RegExp(r'[^\d]'), '');
    final name = _nameController.text.trim();
    bool valid = true;

    if (iin.isEmpty || iin.length != 12) {
      setState(() => _iinError = 'Введите корректный ИИН (12 цифр)');
      valid = false;
    } else {
      setState(() => _iinError = null);
    }

    if (name.isEmpty) {
      setState(() => _nameError = 'Введите ФИО покойного');
      valid = false;
    } else {
      setState(() => _nameError = null);
    }

    if (!valid) return;

    setState(() => _saving = true);
    try {
      await _api.createBurialRequest(
        cemeteryId: widget.cemetery.id,
        fullName: name,
        inn: iin,
        graveId: widget.grave.id,
        deathCertUrl: null,
      );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      String msg = 'Ошибка при бронировании';
      if (e is ApiException) {
        msg = e.body?['message']?.toString() ?? e.message;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSuccess() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.buttonBackground.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                color: AppColors.buttonBackground, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Заявка отправлена!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                  color: AppColors.iconAndText)),
          const SizedBox(height: 10),
          Text(
            'Бронирование места на кладбище «${widget.cemetery.name}» создано. '
            'У вас есть $_bookingDays дня для оплаты.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.iconAndText.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.buttonBackground,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // back to map
              },
              child: const Text('Готово', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  String _preview(String? text) {
    final t = text?.trim();
    return (t == null || t.isEmpty) ? 'Не указано' : t;
  }

  static String _shortName(String full) {
    if (full.isEmpty) return 'Менеджер';
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0]} ${parts[1][0].toUpperCase()}.';
    return parts[0];
  }

  String _religionIconPath() => widget.cemetery.religion == 'Ислам'
      ? 'assets/icons/religions/003-islam.svg'
      : 'assets/icons/religions/christianity.svg';

  static InputDecoration _fieldDec(String hint,
      {Widget? suffix, bool readOnly = false}) {
    const bc = Color(0xFFDDDDDD);
    const r  = 12.0;
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      filled: true,
      fillColor: readOnly ? const Color(0xFFF6F4EF) : Colors.white,
      border:            OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: bc)),
      enabledBorder:     OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: bc)),
      focusedBorder:     OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: AppColors.buttonBackground, width: 1.5)),
      disabledBorder:    OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: bc)),
      errorBorder:       OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: Color(0xFFE53935))),
      focusedErrorBorder:OutlineInputBorder(borderRadius: BorderRadius.circular(r), borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5)),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authManager  = AuthStateManager();
    final displayName  = authManager.getDisplayName();
    final short        = _shortName(displayName);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: OrynaiAppBar(
        title: 'Кабинет менеджера',
        showLogo: true,
        showBack: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'logout') {
                authManager.logout().then((_) {
                  if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                });
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'info',
                enabled: false,
                child: Text(
                  displayName.isNotEmpty ? displayName : 'Менеджер',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.iconAndText),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Выйти', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ],
            offset: const Offset(0, 48),
            child: Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.iconAndText),
                  const SizedBox(width: 6),
                  Text(short, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.iconAndText)),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final listW = (constraints.maxWidth * 0.36).clamp(200.0, min(400.0, constraints.maxWidth * 0.46)).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Сайдбар ────────────────────────────────────────────────────────
            SizedBox(
              width: listW,
              child: ColoredBox(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSizes.paddingMedium),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Row(children: [
                        Icon(Icons.arrow_back, size: 16, color: AppColors.buttonBackground),
                        SizedBox(width: 6),
                        Text('Вернуться к выбору места',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppColors.buttonBackground)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SvgPicture.asset(_religionIconPath(), width: 22, height: 22,
                          colorFilter: const ColorFilter.mode(AppColors.iconAndText, BlendMode.srcIn),
                          placeholderBuilder: (_) => const Icon(Icons.place, size: 22, color: AppColors.iconAndText)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.cemetery.name.toUpperCase(),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                              color: AppColors.iconAndText, height: 1.2))),
                    ]),
                    const SizedBox(height: 16),
                    // Карточка сводки
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F0E7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _summaryRow('Срок брони:', '$_bookingDays дня',
                            info: 'После подачи заявки у вас есть $_bookingDays дня для оплаты.'),
                        const SizedBox(height: 14),
                        Row(children: [
                          _summaryLabel('Сектор: '), _summaryValue(widget.grave.sectorNumber),
                          const SizedBox(width: 20),
                          _summaryLabel('Место: '),  _summaryValue(widget.grave.graveNumber),
                        ]),
                        _divider(),
                        Text.rich(TextSpan(children: [
                          _summarySpan('ФИО покойного: '),
                          _valueSpan(_preview(_nameController.text)),
                        ])),
                        _divider(),
                        Text.rich(TextSpan(children: [
                          _summarySpan('Дата похорон: '),
                          _valueSpan(_preview(_burialDateController.text)),
                        ])),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            // ── Форма ─────────────────────────────────────────────────────────
            Expanded(
              child: ColoredBox(
                color: AppColors.background,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12, offset: const Offset(0, 2))],
                    ),
                    padding: const EdgeInsets.all(AppSizes.paddingLarge),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('ЗАПОЛНЕНИЕ ДАННЫХ',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                              color: AppColors.iconAndText, letterSpacing: 0.5)),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFE8E4DC)),
                      const SizedBox(height: 20),
                      const Text('Укажите данные покойного',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                              color: AppColors.iconAndText)),
                      const SizedBox(height: 12),

                      // ИИН
                      _label('ИИН покойного *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _iinController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        decoration: _fieldDec('ИИН (12 цифр)',
                            suffix: _loadingIin
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2,
                                            color: AppColors.buttonBackground)),
                                  )
                                : _iinController.text.replaceAll(RegExp(r'[^\d]'), '').length == 12
                                    ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20)
                                    : null),
                      ),
                      if (_iinError != null) ...[
                        const SizedBox(height: 4),
                        Text(_iinError!, style: const TextStyle(fontSize: 12, color: Color(0xFFE53935))),
                      ],
                      const SizedBox(height: 12),

                      // ФИО
                      _label('ФИО покойного *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        enabled: !_nameFromApi,
                        decoration: _fieldDec('Иванов Иван Иванович', readOnly: _nameFromApi,
                            suffix: _nameFromApi
                                ? const Tooltip(
                                    message: 'ФИО получено автоматически по ИИН',
                                    child: Icon(Icons.lock_outline, size: 18, color: AppColors.iconAndText))
                                : null),
                      ),
                      if (_nameError != null) ...[
                        const SizedBox(height: 4),
                        Text(_nameError!, style: const TextStyle(fontSize: 12, color: Color(0xFFE53935))),
                      ],
                      const SizedBox(height: 20),

                      // Переключатель дат
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Даты',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                color: AppColors.iconAndText)),
                        Switch(
                          value: _datesEnabled,
                          onChanged: (v) => setState(() => _datesEnabled = v),
                          activeColor: AppColors.buttonBackground,
                        ),
                      ]),

                      // Блок дат (если включён)
                      if (_datesEnabled) ...[
                        const SizedBox(height: 16),

                        // Дата смерти
                        _label('Дата смерти'),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _pickDeathDate,
                          child: TextFormField(
                            controller: _deathDateController,
                            enabled: false,
                            decoration: _fieldDec('дд.мм.гггг', readOnly: true,
                                suffix: const Icon(Icons.calendar_today, size: 18,
                                    color: AppColors.iconAndText)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Свидетельство о смерти
                        _label('Свидетельство о смерти'),
                        const SizedBox(height: 6),
                        _buildCertField(),
                        const SizedBox(height: 16),

                        // Дата похорон
                        _label('Дата похорон'),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _pickBurialDate,
                          child: TextFormField(
                            controller: _burialDateController,
                            enabled: false,
                            decoration: _fieldDec('дд.мм.гггг', readOnly: true,
                                suffix: const Icon(Icons.calendar_today, size: 18,
                                    color: AppColors.iconAndText)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Время похорон
                        _label('Время похорон'),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _pickBurialTime,
                          child: TextFormField(
                            controller: _burialTimeController,
                            enabled: false,
                            decoration: _fieldDec('чч:мм', readOnly: true,
                                suffix: const Icon(Icons.access_time, size: 18,
                                    color: AppColors.iconAndText)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),
                      // Кнопка
                      Center(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.buttonBackground,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _saving
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Забронировать место',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ─── Вспомогательные виджеты ────────────────────────────────────────────────

  Widget _label(String text) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
          color: AppColors.iconAndText.withValues(alpha: 0.75)));

  Widget _summaryRow(String label, String value, {String? info}) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _summaryLabel(label),
          const SizedBox(width: 6),
          _summaryValue(value),
          if (info != null) ...[
            const SizedBox(width: 6),
            Tooltip(message: info,
                child: Icon(Icons.info_outline, size: 17,
                    color: _labelColor.withValues(alpha: 0.45))),
          ],
        ],
      );

  Widget _summaryLabel(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Manrope', fontSize: 13,
          fontWeight: FontWeight.w500, color: _labelColor, height: 1.3));

  Widget _summaryValue(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Manrope', fontSize: 13,
          fontWeight: FontWeight.w400, color: _valueColor, height: 1.3));

  TextSpan _summarySpan(String t) => TextSpan(text: t,
      style: const TextStyle(fontFamily: 'Manrope', fontSize: 13,
          fontWeight: FontWeight.w500, color: _labelColor, height: 1.35));

  TextSpan _valueSpan(String t) => TextSpan(text: t,
      style: const TextStyle(fontFamily: 'Manrope', fontSize: 13,
          fontWeight: FontWeight.w400, color: _valueColor, height: 1.35));

  Widget _divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, thickness: 1, color: _dividerColor));

  Widget _buildCertField() {
    if (_certFile != null) {
      final name     = _certFile!.path.split('/').last;
      final sizeKb   = _certFile!.lengthSync() / 1024;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(children: [
          const Icon(Icons.insert_drive_file, color: AppColors.iconAndText, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                color: AppColors.iconAndText), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${sizeKb.toStringAsFixed(1)} KB',
                style: TextStyle(fontSize: 12, color: AppColors.iconAndText.withValues(alpha: 0.5))),
          ])),
          IconButton(icon: const Icon(Icons.close, size: 18), color: AppColors.iconAndText,
              onPressed: _removeCert),
        ]),
      );
    }
    return GestureDetector(
      onTap: _pickCert,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.upload_file, color: AppColors.iconAndText, size: 22),
          const SizedBox(width: 8),
          Text('Загрузить файл',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                  color: AppColors.iconAndText.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }
}
