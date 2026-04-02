import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../widgets/orynai_app_bar.dart';
import '../models/burial_record.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/audit_service.dart';
import '../services/local_db_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';

class GraveDetailPage extends StatefulWidget {
  final Grave grave;
  final Cemetery cemetery;

  const GraveDetailPage({
    super.key,
    required this.grave,
    required this.cemetery,
  });

  @override
  State<GraveDetailPage> createState() => _GraveDetailPageState();
}

class _GraveDetailPageState extends State<GraveDetailPage> {
  final LocalDbService _db = LocalDbService();
  final LocationService _locationService = LocationService();
  final SyncService _syncService = SyncService();
  final AuditService _audit = AuditService();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _iinController = TextEditingController();
  final _deathDateController = TextEditingController();
  final _burialDateController = TextEditingController();
  final _notesController = TextEditingController();

  BurialRecord? _existingRecord;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isFixingGps = false;

  double? _latitude;
  double? _longitude;
  double? _gpsAccuracy;
  DateTime? _gpsFixedAt;

  @override
  void initState() {
    super.initState();
    _loadExistingRecord();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iinController.dispose();
    _deathDateController.dispose();
    _burialDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRecord() async {
    final record = await _db.getBurialRecordByGraveId(widget.grave.id);
    if (mounted) {
      setState(() {
        _existingRecord = record;
        if (record != null) {
          _nameController.text = record.deceasedName ?? '';
          _iinController.text = record.deceasedIin ?? '';
          _deathDateController.text = record.deathDate ?? '';
          _burialDateController.text = record.burialDate ?? '';
          _notesController.text = record.notes ?? '';
          _latitude = record.latitude;
          _longitude = record.longitude;
          _gpsAccuracy = record.gpsAccuracy;
          _gpsFixedAt = record.gpsFixedAt;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _fixGpsCoordinates() async {
    setState(() => _isFixingGps = true);

    try {
      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Не удалось получить координаты. Проверьте GPS-сигнал.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsAccuracy = position.accuracy;
        _gpsFixedAt = DateTime.now();
      });

      _audit.log(
        action: AuditAction.fixCoordinates,
        entityType: 'grave',
        entityId: widget.grave.id,
        details: 'lat=${position.latitude.toStringAsFixed(6)}'
            ',lon=${position.longitude.toStringAsFixed(6)}'
            ',acc=${position.accuracy.toStringAsFixed(1)}m',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Координаты зафиксированы: '
              '${position.latitude.toStringAsFixed(6)}, '
              '${position.longitude.toStringAsFixed(6)} '
              '(±${position.accuracy.toStringAsFixed(1)} м)',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFixingGps = false);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.buttonBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      controller.text = DateFormat('dd.MM.yyyy').format(picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final record = BurialRecord(
        id: _existingRecord?.id,
        graveId: widget.grave.id,
        cemeteryId: widget.cemetery.id,
        deceasedName: _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : null,
        deceasedIin: _iinController.text.trim().isNotEmpty
            ? _iinController.text.trim()
            : null,
        deathDate: _deathDateController.text.trim().isNotEmpty
            ? _deathDateController.text.trim()
            : null,
        burialDate: _burialDateController.text.trim().isNotEmpty
            ? _burialDateController.text.trim()
            : null,
        latitude: _latitude,
        longitude: _longitude,
        gpsAccuracy: _gpsAccuracy,
        gpsFixedAt: _gpsFixedAt,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      final saved = await _syncService.saveBurialRecord(record);
      setState(() => _existingRecord = saved);

      _audit.log(
        action: AuditAction.saveGraveRecord,
        entityType: 'grave',
        entityId: widget.grave.id,
        details: 'status=${saved.syncStatus.name},grave=${widget.grave.fullNumber}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved.syncStatusLabel),
            backgroundColor:
                saved.syncStatus == SyncStatus.synced
                    ? Colors.green
                    : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

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
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Color _syncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.pending:
        return Colors.orange;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.local:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: OrynaiAppBar(
        title: 'Место ${widget.grave.sectorNumber}-'
            '${widget.grave.rowNumber}-'
            '${widget.grave.graveNumber}',
        showBack: true,
        actions: [
          if (_existingRecord != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(
                  _existingRecord!.syncStatusLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: _syncStatusColor(_existingRecord!.syncStatus),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.buttonBackground),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSizes.paddingMedium),
                children: [
                  // Статус места
                  _SectionCard(
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: _statusColor(widget.grave.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _statusLabel(widget.grave.status),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _statusColor(widget.grave.status),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.cemetery.name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.iconAndText,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSizes.paddingMedium),

                  // Данные о захоронении
                  _SectionCard(
                    title: 'Данные о захоронении',
                    child: Column(
                      children: [
                        _FormField(
                          controller: _nameController,
                          label: 'ФИО покойного',
                          hint: 'Фамилия Имя Отчество',
                          icon: Icons.person,
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _iinController,
                          label: 'ИИН',
                          hint: '000000000000',
                          icon: Icons.badge,
                          keyboardType: TextInputType.number,
                          maxLength: 12,
                        ),
                        const SizedBox(height: 12),
                        _DateFormField(
                          controller: _deathDateController,
                          label: 'Дата смерти',
                          onTap: () => _pickDate(_deathDateController),
                        ),
                        const SizedBox(height: 12),
                        _DateFormField(
                          controller: _burialDateController,
                          label: 'Дата захоронения',
                          onTap: () => _pickDate(_burialDateController),
                        ),
                        const SizedBox(height: 12),
                        _FormField(
                          controller: _notesController,
                          label: 'Примечание',
                          hint: 'Дополнительная информация...',
                          icon: Icons.notes,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSizes.paddingMedium),

                  // GPS координаты
                  _SectionCard(
                    title: 'GPS координаты',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_latitude != null && _longitude != null) ...[
                          _CoordRow(
                            icon: Icons.my_location,
                            label: 'Широта',
                            value: _latitude!.toStringAsFixed(7),
                          ),
                          const SizedBox(height: 4),
                          _CoordRow(
                            icon: Icons.my_location,
                            label: 'Долгота',
                            value: _longitude!.toStringAsFixed(7),
                          ),
                          if (_gpsAccuracy != null) ...[
                            const SizedBox(height: 4),
                            _CoordRow(
                              icon: Icons.gps_fixed,
                              label: 'Точность',
                              value: '±${_gpsAccuracy!.toStringAsFixed(1)} м',
                            ),
                          ],
                          if (_gpsFixedAt != null) ...[
                            const SizedBox(height: 4),
                            _CoordRow(
                              icon: Icons.access_time,
                              label: 'Зафиксировано',
                              value: DateFormat(
                                'dd.MM.yyyy HH:mm',
                              ).format(_gpsFixedAt!),
                            ),
                          ],
                          const SizedBox(height: 12),
                        ] else ...[
                          const Row(
                            children: [
                              Icon(
                                Icons.gps_not_fixed,
                                size: 16,
                                color: AppColors.iconAndText,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Координаты не зафиксированы',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _isFixingGps ? null : _fixGpsCoordinates,
                            icon: _isFixingGps
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.buttonBackground,
                                    ),
                                  )
                                : const Icon(
                                    Icons.gps_fixed,
                                    size: 18,
                                    color: AppColors.buttonBackground,
                                  ),
                            label: Text(
                              _isFixingGps
                                  ? 'Получаем координаты...'
                                  : (_latitude != null
                                      ? 'Обновить координаты'
                                      : 'Зафиксировать координаты'),
                              style: const TextStyle(
                                color: AppColors.buttonBackground,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.buttonBackground,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSizes.paddingMedium),

                  // Информация об устройстве (аудит)
                  if (_existingRecord != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFAFB5C1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tablet_android,
                            size: 16,
                            color: AppColors.iconAndText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Действие выполнено с планшета '
                              '(${_existingRecord!.deviceSource})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.iconAndText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppSizes.paddingXLarge),

                  // Кнопка сохранения
                  SizedBox(
                    width: double.infinity,
                    height: AppSizes.buttonHeight,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.save,
                              color: Colors.white,
                              size: 20,
                            ),
                      label: Text(
                        _isSaving ? 'Сохранение...' : 'Сохранить',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonBackground,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSizes.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSizes.paddingMedium),
                ],
              ),
            ),
    );
  }
}

// ─── Вспомогательные виджеты ─────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final String? title;

  const _SectionCard({required this.child, this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.paddingMedium),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.iconAndText,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.iconAndText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18, color: AppColors.iconAndText),
            filled: true,
            fillColor: const Color(0xFFF4F0E7),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.buttonBackground,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _DateFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;

  const _DateFormField({
    required this.controller,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.iconAndText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: 'дд.мм.гггг',
            prefixIcon: const Icon(
              Icons.calendar_today,
              size: 18,
              color: AppColors.iconAndText,
            ),
            filled: true,
            fillColor: const Color(0xFFF4F0E7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.buttonBackground,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoordRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CoordRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.iconAndText),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: AppColors.iconAndText),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.iconAndText,
          ),
        ),
      ],
    );
  }
}
