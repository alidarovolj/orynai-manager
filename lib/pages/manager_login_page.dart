import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/auth_state_manager.dart';
import 'manager_home_page.dart';

enum _LoginStep { phone, code }

class ManagerLoginPage extends StatefulWidget {
  const ManagerLoginPage({super.key});

  @override
  State<ManagerLoginPage> createState() => _ManagerLoginPageState();
}

class _ManagerLoginPageState extends State<ManagerLoginPage> {
  final AuthService _authService = AuthService();
  _LoginStep _currentStep = _LoginStep.phone;

  // ─── Шаг 1: Телефон ────────────────────────────────────────────────────────

  final TextEditingController _phoneController = TextEditingController();
  bool _isLoadingPhone = false;
  String _phone = '';

  // ─── Шаг 2: Код ────────────────────────────────────────────────────────────

  final List<TextEditingController> _codeControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _codeFocusNodes =
      List.generate(4, (_) => FocusNode());
  bool _isLoadingCode = false;
  int _resendTimer = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_formatPhone);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _phoneController
      ..removeListener(_formatPhone)
      ..dispose();
    for (final c in _codeControllers) { c.dispose(); }
    for (final f in _codeFocusNodes) { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  // ─── Форматирование телефона ───────────────────────────────────────────────

  void _formatPhone() {
    final digits = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length > 11) {
      _applyFormatted(_buildMasked(digits.substring(0, 11)));
      return;
    }
    _applyFormatted(_buildMasked(digits));
  }

  String _buildMasked(String digits) {
    if (digits.isEmpty) return '';
    String d = digits.startsWith('7') ? digits : '7$digits';
    String result = '+7';
    if (d.length > 1) result += ' (${d.substring(1, d.length > 4 ? 4 : d.length)}';
    if (d.length > 4) result += ') ${d.substring(4, d.length > 7 ? 7 : d.length)}';
    if (d.length > 7) result += '-${d.substring(7, d.length > 9 ? 9 : d.length)}';
    if (d.length > 9) result += '-${d.substring(9)}';
    return result;
  }

  void _applyFormatted(String formatted) {
    if (formatted == _phoneController.text) return;
    _phoneController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _getCleanPhone() =>
      _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');

  // ─── Шаг 1: Отправка кода ─────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = _getCleanPhone();
    if (phone.length < 11 || !phone.startsWith('7')) {
      _showSnack('Введите корректный номер телефона');
      return;
    }

    setState(() => _isLoadingPhone = true);
    try {
      final result = await _authService.sendOtpWhatsApp(phone);
      if (!mounted) return;
      if (result == 'OK') {
        setState(() {
          _phone = phone;
          _currentStep = _LoginStep.code;
          _resendTimer = 60;
        });
        _startTimer();
      } else {
        _showSnack('Ошибка: $result');
      }
    } catch (e) {
      if (mounted) _showSnack('Не удалось отправить код: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPhone = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendTimer > 0) {
          _resendTimer--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ─── Шаг 2: Верификация кода ───────────────────────────────────────────────

  String _getCode() => _codeControllers.map((c) => c.text).join();

  void _handleCodeInput(int index, String value) {
    if (value.isNotEmpty) {
      if (index < 3) {
        _codeFocusNodes[index + 1].requestFocus();
      } else {
        _codeFocusNodes[index].unfocus();
        _verifyCode();
      }
    } else if (value.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final code = _getCode();
    if (code.length != 4) { _showSnack('Введите 4-значный код'); return; }

    setState(() => _isLoadingCode = true);
    try {
      final result = await _authService.verifyOtpWhatsApp(_phone, code);
      if (!mounted) return;

      if (result['success'] == true) {
        final token = result['token']?.toString() ?? '';
        if (token.isEmpty) { _showSnack('Ошибка: токен не получен'); return; }

        final data = result['data'] as Map<String, dynamic>? ?? {};
        final user = User(
          phone: data['phone']?.toString() ?? _phone,
          token: token,
          name: data['name']?.toString(),
          surname: data['surname']?.toString(),
          patronymic: data['patronymic']?.toString(),
          iin: data['iin']?.toString(),
        );
        await AuthStateManager().setUser(user);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ManagerHomePage()),
        );
      } else if (result['needsRegistration'] == true) {
        _showSnack('Аккаунт не зарегистрирован. Обратитесь к администратору.');
      } else {
        final desc = result['error']?['description']?.toString();
        _showSnack(desc ?? 'Неверный код. Попробуйте ещё раз.');
      }
    } catch (e) {
      if (mounted) _showSnack('Ошибка проверки кода: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCode = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.iconAndText,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatPhoneForDisplay(String phone) {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+7 (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-'
          '${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Используем MediaQuery.size — не меняется при открытии клавиатуры,
    // поэтому макет не перестраивается и поле не теряет фокус.
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isTablet = screenSize.width > 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: isTablet && isLandscape
          ? _buildTabletLandscape(screenSize)
          : _buildPortrait(screenSize, isTablet: isTablet),
    );
  }

  // ── Планшет горизонталь: логотип слева, форма справа ──────────────────────

  Widget _buildTabletLandscape(Size screenSize) {
    final h = screenSize.height;
    return Row(
      children: [
        // Левая панель — брендинг
        Expanded(
          flex: 4,
          child: Container(
            color: AppColors.buttonBackground,
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logos/main.png',
                  height: h * 0.18,
                  errorBuilder: (_, __, ___) => SvgPicture.asset(
                    'assets/images/logos/logo.svg',
                    height: h * 0.18,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                SizedBox(height: h * 0.04),
                Text(
                  'Orynai Manager',
                  style: TextStyle(
                    fontSize: h * 0.055,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: h * 0.015),
                Text(
                  'Система управления кладбищем',
                  style: TextStyle(
                    fontSize: h * 0.028,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        // Правая панель — форма
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.06,
                vertical: 32,
              ),
              child: _buildFormCard(screenSize: screenSize),
            ),
          ),
        ),
      ],
    );
  }

  // ── Портрет / телефон: логотип + карточка по центру ───────────────────────

  Widget _buildPortrait(Size screenSize, {required bool isTablet}) {
    final w = screenSize.width;
    final h = screenSize.height;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? w * 0.12 : 24,
            vertical: 32,
          ),
          child: Column(
            children: [
              Image.asset(
                'assets/images/logos/main.png',
                height: h * 0.12,
                errorBuilder: (_, __, ___) => SvgPicture.asset(
                  'assets/images/logos/logo.svg',
                  height: h * 0.12,
                ),
              ),
              SizedBox(height: h * 0.02),
              Text(
                'Orynai Manager',
                style: TextStyle(
                  fontSize: isTablet ? 30 : 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.iconAndText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Система управления кладбищем',
                style: TextStyle(
                  fontSize: isTablet ? 17 : 13,
                  color: AppColors.iconAndText.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: h * 0.04),
              _buildFormCard(screenSize: screenSize),
            ],
          ),
        ),
      ),
    );
  }

  // ── Карточка формы ─────────────────────────────────────────────────────────

  Widget _buildFormCard({required Size screenSize}) {
    final w = screenSize.width;
    final h = screenSize.height;
    final isLandscape = w > h;
    final isTablet = w > 600;

    // Размеры шрифтов и элементов масштабируются под экран
    final titleSize = isTablet ? (isLandscape ? h * 0.045 : 28.0) : 20.0;
    final labelSize = isTablet ? (isLandscape ? h * 0.028 : 17.0) : 14.0;
    final inputFontSize = isTablet ? 20.0 : 16.0;
    final inputHeight = isTablet ? 64.0 : 52.0;
    final btnHeight = isTablet ? 70.0 : 56.0;
    final btnFontSize = isTablet ? 20.0 : 16.0;
    final cardPadding = isTablet ? 40.0 : 24.0;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.iconAndText.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _currentStep == _LoginStep.phone
          ? _buildPhoneStep(
              titleSize: titleSize,
              labelSize: labelSize,
              inputFontSize: inputFontSize,
              inputHeight: inputHeight,
              btnHeight: btnHeight,
              btnFontSize: btnFontSize,
            )
          : _buildCodeStep(
              titleSize: titleSize,
              labelSize: labelSize,
              inputFontSize: inputFontSize,
              btnHeight: btnHeight,
              btnFontSize: btnFontSize,
            ),
    );
  }

  // ─── Шаг 1: ввод телефона ─────────────────────────────────────────────────

  Widget _buildPhoneStep({
    required double titleSize,
    required double labelSize,
    required double inputFontSize,
    required double inputHeight,
    required double btnHeight,
    required double btnFontSize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Вход',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: AppColors.iconAndText,
          ),
        ),
        SizedBox(height: labelSize * 0.4),
        Text(
          'Введите номер — отправим код в WhatsApp',
          style: TextStyle(
            fontSize: labelSize,
            color: AppColors.iconAndText.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: inputHeight * 0.4),
        AutofillGroup(
          child: _inputField(
            controller: _phoneController,
            hint: '+7 (7__) ___-__-__',
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            fontSize: inputFontSize,
            height: inputHeight,
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\(\)\-]'))],
          ),
        ),
        SizedBox(height: btnHeight * 0.35),
        _primaryButton(
          label: 'Получить код в WhatsApp',
          isLoading: _isLoadingPhone,
          onPressed: _sendOtp,
          height: btnHeight,
          fontSize: btnFontSize,
        ),
      ],
    );
  }

  // ─── Шаг 2: ввод кода ─────────────────────────────────────────────────────

  Widget _buildCodeStep({
    required double titleSize,
    required double labelSize,
    required double inputFontSize,
    required double btnHeight,
    required double btnFontSize,
  }) {
    final codeBoxSize = btnHeight * 1.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Подтверждение',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: AppColors.iconAndText,
          ),
        ),
        SizedBox(height: labelSize * 0.4),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: labelSize,
              color: AppColors.iconAndText.withValues(alpha: 0.6),
            ),
            children: [
              const TextSpan(text: 'Код отправлен на '),
              TextSpan(
                text: _formatPhoneForDisplay(_phone),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.iconAndText,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: codeBoxSize * 0.35),
        // 4 поля ввода кода
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (i) {
            return SizedBox(
              width: codeBoxSize,
              height: codeBoxSize,
              child: TextField(
                controller: _codeControllers[i],
                focusNode: _codeFocusNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: TextStyle(
                  fontSize: inputFontSize * 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.iconAndText,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.accordionBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.accordionBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.buttonBackground,
                      width: 2.5,
                    ),
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => _handleCodeInput(i, v),
              ),
            );
          }),
        ),
        SizedBox(height: btnHeight * 0.3),
        GestureDetector(
          onTap: _resendTimer == 0 ? _sendOtp : null,
          child: Text(
            _resendTimer > 0
                ? 'Отправить повторно через $_resendTimer сек'
                : 'Отправить код повторно',
            style: TextStyle(
              fontSize: labelSize,
              color: _resendTimer > 0
                  ? AppColors.accordionBorder
                  : AppColors.buttonBackground,
              fontWeight:
                  _resendTimer > 0 ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: btnHeight * 0.3),
        _primaryButton(
          label: 'Подтвердить',
          isLoading: _isLoadingCode,
          onPressed: _verifyCode,
          height: btnHeight,
          fontSize: btnFontSize,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            _timer?.cancel();
            setState(() {
              _currentStep = _LoginStep.phone;
              for (final c in _codeControllers) { c.clear(); }
            });
          },
          icon: Icon(Icons.arrow_back, size: labelSize),
          label: Text('Изменить номер'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.iconAndText.withValues(alpha: 0.6),
            padding: EdgeInsets.zero,
            textStyle: TextStyle(fontSize: labelSize),
          ),
        ),
      ],
    );
  }

  // ─── Переиспользуемые виджеты ─────────────────────────────────────────────

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    required IconData prefixIcon,
    required double fontSize,
    required double height,
    List<TextInputFormatter>? formatters,
  }) {
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [],
        style: TextStyle(
          color: AppColors.iconAndText,
          fontSize: fontSize,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.accordionBorder.withValues(alpha: 0.8),
            fontSize: fontSize,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: AppColors.accordionBorder,
            size: fontSize * 1.2,
          ),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: (height - fontSize * 1.4) / 2,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppColors.accordionBorder.withValues(alpha: 0.4),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppColors.accordionBorder.withValues(alpha: 0.4),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.buttonBackground,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    required double height,
    required double fontSize,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonBackground,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.buttonBackground.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: fontSize * 1.4,
                height: fontSize * 1.4,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
