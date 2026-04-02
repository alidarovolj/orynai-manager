import 'dart:io' show File;
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models/cemetery.dart';
import '../models/grave.dart';
import '../services/api_service.dart';

/// Экран бронирования: слева сводка по кладбищу и месту, справа форма (макет «Заполнение данных»).
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _iinController = TextEditingController();
  final _birthController = TextEditingController();
  final _deathController = TextEditingController();

  bool _saving = false;
  XFile? _photo;

  static const int _bookingDays = 3;

  static const Color _bookingSummaryLabelColor = Color(0xFF201001);
  static const Color _bookingSummaryValueColor = Color(0xFF8A8580);
  static const Color _bookingSummaryDividerColor = Color(0xFFE5E0D8);

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _deathController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iinController.dispose();
    _birthController.dispose();
    _deathController.dispose();
    super.dispose();
  }

  String _preview(String? text) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return 'Не указано';
    return t;
  }

  Future<void> _pickBirthDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(1950),
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
    if (d != null) {
      _birthController.text = DateFormat('dd.MM.yyyy').format(d);
    }
  }

  Future<void> _pickDeathDate() async {
    final d = await showDatePicker(
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
    if (d != null) {
      _deathController.text = DateFormat('dd.MM.yyyy').format(d);
    }
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file != null) setState(() => _photo = file);
  }

  String _plotAreaLabel() {
    final w = widget.grave.width;
    final h = widget.grave.height;
    if (w <= 0 || h <= 0) return '';
    final fmt = NumberFormat.decimalPattern('ru');
    // ≥10 — дециметры (25 → 2,5 м), иначе целые метры из API
    final wm = (w >= 10 || h >= 10) ? w / 10.0 : w.toDouble();
    final hm = (w >= 10 || h >= 10) ? h / 10.0 : h.toDouble();
    return '${fmt.format(wm)}х${fmt.format(hm)}м';
  }

  Future<void> _onSavePressed() async {
    if (!_formKey.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _BookingConfirmDialog(
          cemeteryName: widget.cemetery.name,
          sector: widget.grave.sectorNumber,
          place: widget.grave.graveNumber,
          areaLabel: _plotAreaLabel(),
          fullName: _nameController.text.trim(),
          iin: _iinController.text.trim().replaceAll(RegExp(r'\s'), ''),
          birth: _birthController.text.trim(),
          death: _deathController.text.trim(),
          photo: _photo,
        );
      },
    );
    if (confirmed == true && mounted) {
      await _submit();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiService().createBurialRequest(
        cemeteryId: widget.cemetery.id,
        fullName: _nameController.text.trim(),
        inn: _iinController.text.trim().replaceAll(RegExp(r'\s'), ''),
        graveId: widget.grave.id,
        deathCertUrl: '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отправлена')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _religionIconPath() {
    return widget.cemetery.religion == 'Ислам'
        ? 'assets/icons/religions/003-islam.svg'
        : 'assets/icons/religions/christianity.svg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Бронирование места',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.iconAndText,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.iconAndText),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final listW =
              (w * 0.36).clamp(200.0, min(400.0, w * 0.46)).toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSizes.paddingMedium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: AppColors.buttonBackground,
                          ),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text(
                            'Вернуться к выбору места',
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
                              _religionIconPath(),
                              width: 22,
                              height: 22,
                              colorFilter: const ColorFilter.mode(
                                AppColors.iconAndText,
                                BlendMode.srcIn,
                              ),
                              placeholderBuilder: (_) => const Icon(
                                Icons.place,
                                size: 22,
                                color: AppColors.iconAndText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.cemetery.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.iconAndText,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F0E7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Срок брони:',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _bookingSummaryLabelColor,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_bookingDays дня',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: _bookingSummaryValueColor,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message:
                                        'После подачи заявки у вас есть $_bookingDays дня для оплаты и подтверждения.',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 17,
                                      color: _bookingSummaryLabelColor
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Text(
                                    'Сектор: ',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _bookingSummaryLabelColor,
                                      height: 1.3,
                                    ),
                                  ),
                                  Text(
                                    widget.grave.sectorNumber,
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: _bookingSummaryValueColor,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Text(
                                    'Место: ',
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _bookingSummaryLabelColor,
                                      height: 1.3,
                                    ),
                                  ),
                                  Text(
                                    widget.grave.graveNumber,
                                    style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: _bookingSummaryValueColor,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _bookingSummaryDividerColor,
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'ФИО покойного: ',
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _bookingSummaryLabelColor,
                                        height: 1.35,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _preview(_nameController.text),
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: _bookingSummaryValueColor,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _bookingSummaryDividerColor,
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Дата похорон: ',
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _bookingSummaryLabelColor,
                                        height: 1.35,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _preview(_deathController.text),
                                      style: TextStyle(
                                        fontFamily: 'Manrope',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: _bookingSummaryValueColor,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSizes.paddingLarge),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ЗАПОЛНЕНИЕ ДАННЫХ',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.iconAndText,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Укажите данные покойного',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.iconAndText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: 'ФИО',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Введите ФИО';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _iinController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'ИИН (12 цифр)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) {
                              final d = v?.replaceAll(RegExp(r'\s'), '') ?? '';
                              if (d.length != 12 ||
                                  int.tryParse(d) == null) {
                                return 'Введите корректный ИИН';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Даты',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.iconAndText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _birthController,
                                  readOnly: true,
                                  onTap: _pickBirthDate,
                                  decoration: InputDecoration(
                                    hintText: 'Дата рождения',
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixIcon: const Icon(Icons.calendar_today,
                                        size: 18),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _deathController,
                                  readOnly: true,
                                  onTap: _pickDeathDate,
                                  decoration: InputDecoration(
                                    hintText: 'Дата смерти',
                                    filled: true,
                                    fillColor: Colors.white,
                                    suffixIcon: const Icon(Icons.calendar_today,
                                        size: 18),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _takePhoto,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 32,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.accordionBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.photo_camera_outlined,
                                      size: 40,
                                      color: AppColors.iconAndText
                                          .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _photo == null
                                          ? 'Сделать фото'
                                          : 'Фото добавлено',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.iconAndText
                                            .withValues(alpha: 0.8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _saving ? null : _onSavePressed,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.buttonBackground,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Сохранить данные',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Модалка подтверждения перед отправкой заявки на бронирование.
class _BookingConfirmDialog extends StatelessWidget {
  final String cemeteryName;
  final String sector;
  final String place;
  final String areaLabel;
  final String fullName;
  final String iin;
  final String birth;
  final String death;
  final XFile? photo;

  const _BookingConfirmDialog({
    required this.cemeteryName,
    required this.sector,
    required this.place,
    required this.areaLabel,
    required this.fullName,
    required this.iin,
    required this.birth,
    required this.death,
    required this.photo,
  });

  static const double _galleryH = 200;

  @override
  Widget build(BuildContext context) {
    final path = photo?.path;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      height: _galleryH,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _ConfirmPhotoTile(path: path),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: Column(
                              children: [
                                Expanded(
                                  child: _ConfirmPhotoTile(path: path),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _ConfirmPhotoTile(path: path),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 22),
                          color: AppColors.iconAndText,
                          onPressed: () => Navigator.of(context).pop(false),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cemeteryName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.iconAndText,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(label: 'Сектор: $sector'),
                        _InfoChip(label: 'Место: $place'),
                        if (areaLabel.isNotEmpty)
                          _InfoChip(label: 'Площадь: $areaLabel'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ConfirmDataRow(
                      label: 'ФИО покойного:',
                      value: fullName.isEmpty ? '—' : fullName,
                      valueBold: true,
                      valueColor: AppColors.iconAndText,
                    ),
                    _ConfirmDataRow(
                      label: 'ИИН:',
                      value: iin.isEmpty ? '—' : iin,
                      muted: true,
                    ),
                    _ConfirmDataRow(
                      label: 'Дата рождения:',
                      value: birth.isEmpty ? '—' : birth,
                      muted: true,
                    ),
                    _ConfirmDataRow(
                      label: 'Дата смерти:',
                      value: death.isEmpty ? '—' : death,
                      muted: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE8E4DC),
                            foregroundColor: AppColors.iconAndText,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Редактировать',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.buttonBackground,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Подтвердить',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFEF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.iconAndText,
        ),
      ),
    );
  }
}

class _ConfirmDataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool valueBold;
  final bool muted;
  final Color? valueColor;

  const _ConfirmDataRow({
    required this.label,
    required this.value,
    this.valueBold = false,
    this.muted = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor =
        muted ? Colors.grey.shade600 : AppColors.iconAndText.withValues(alpha: 0.75);
    final defaultValueColor =
        muted ? Colors.grey.shade600 : AppColors.iconAndText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 12,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 13,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? defaultValueColor,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfirmPhotoTile extends StatelessWidget {
  final String? path;

  const _ConfirmPhotoTile({this.path});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (path != null && path!.isNotEmpty) {
      child = Image.file(
        File(path!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.grey.shade300,
        child: child,
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 36,
        color: Colors.grey.shade500,
      ),
    );
  }
}
