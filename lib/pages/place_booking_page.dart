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
                          padding: const EdgeInsets.all(AppSizes.paddingMedium),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F0E7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Срок брони: $_bookingDays дня',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.iconAndText,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message:
                                        'После подачи заявки у вас есть $_bookingDays дня для оплаты и подтверждения.',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: AppColors.iconAndText
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Сектор: ${widget.grave.sectorNumber}   Место: ${widget.grave.graveNumber}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'ФИО покойного: ${_preview(_nameController.text)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Дата похорон: ${_preview(_deathController.text)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iconAndText
                                      .withValues(alpha: 0.85),
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
                              fillColor: const Color(0xFFF4F0E7),
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
                              fillColor: const Color(0xFFF4F0E7),
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
                                    fillColor: const Color(0xFFF4F0E7),
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
                                    fillColor: const Color(0xFFF4F0E7),
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
                              onPressed: _saving ? null : _submit,
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
