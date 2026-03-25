import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum ServiceBookingType { consult, visit }

class ServiceBookingDraft {
  const ServiceBookingDraft({
    required this.product,
    required this.productType,
    required this.symptom,
    required this.name,
    required this.phoneNumber,
    required this.address,
    required this.detailAddress,
    required this.reservationDate,
    required this.reservationTime,
    this.detailedSymptom,
  });

  final String product;
  final String productType;
  final String symptom;
  final String name;
  final String phoneNumber;
  final String address;
  final String detailAddress;
  final String reservationDate;
  final String reservationTime;
  final String? detailedSymptom;
}

class ServiceBookingFlowScreen extends StatefulWidget {
  const ServiceBookingFlowScreen({
    super.key,
    required this.serviceType,
    required this.baseUrl,
    required this.userId,
    required this.initialUserName,
    required this.initialPhoneNumber,
    required this.initialAddress,
  });

  final ServiceBookingType serviceType;
  final String baseUrl;
  final int userId;
  final String initialUserName;
  final String initialPhoneNumber;
  final String initialAddress;

  @override
  State<ServiceBookingFlowScreen> createState() =>
      _ServiceBookingFlowScreenState();
}

enum _ServiceBookingStep { productInfo, customerInfo, scheduleInfo }

class _ServiceBookingUserProfile {
  const _ServiceBookingUserProfile({
    required this.name,
    required this.phone,
    required this.address,
  });

  factory _ServiceBookingUserProfile.fromJson(Map<String, dynamic> json) {
    return _ServiceBookingUserProfile(
      name: json['name']?.toString().trim() ?? '',
      phone: json['phone']?.toString().trim() ?? '',
      address: json['address']?.toString().trim() ?? '',
    );
  }

  final String name;
  final String phone;
  final String address;
}

class _ServiceBookingFlowScreenState extends State<ServiceBookingFlowScreen> {
  static const _productOptions = ['냉장고/김치냉장고', '세탁기', '에어컨/환기'];
  static const _productTypeOptions = <String, List<String>>{
    '냉장고/김치냉장고': ['양문형 냉장고', '일반형 냉장고', '싱냉장/하냉동', '스탠드형 김치냉장고', '뚜껑형 김치냉장고'],
    '세탁기': ['드럼세탁기', '통돌이 세탁기', '워시타워', '미니세탁기'],
    '에어컨/환기': [
      '2in1 에어컨',
      '스탠드형 에어컨',
      '벽걸이형 에어컨',
      '가정용 천장형 에어컨',
      '상업용 천장형 에어컨',
      '상업용 스탠드 에어컨',
    ],
  };
  static const _symptomOptions = <String, List<String>>{
    '냉장고/김치냉장고': [
      '에러코드/표시창',
      '기능/작동',
      'ThinQ/스마트기능',
      '디스펜서/정수기',
      '구조/외관',
      '누수/결빙/성에/이슬',
      '전원/누전',
      '냉동/냉장',
      '메뉴/작동 방법',
      '도어/홈바',
      '소음/진동',
      '냄새/이물',
    ],
    '세탁기': [
      '에러코드/표시창',
      '기능/작동',
      'ThinQ/스마트기능',
      '디스펜서/정수기',
      '구조/외관',
      '누수/결빙/성에/이슬',
      '전원/누전',
      '냉동/냉장',
      '메뉴/작동 방법',
      '도어/홈바',
      '소음/진동',
      '냄새/이물',
    ],
    '에어컨/환기': [
      '에러코드/표시창',
      '기능/작동',
      'ThinQ/스마트기능',
      '디스펜서/정수기',
      '구조/외관',
      '누수/결빙/성에/이슬',
      '전원/누전',
      '냉동/냉장',
      '메뉴/작동 방법',
      '도어/홈바',
      '소음/진동',
      '냄새/이물',
    ],
  };
  static const _timeSlotOptions = [
    '09:00',
    '10:00',
    '11:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
  ];

  String? _selectedProduct;
  String? _selectedProductType;
  String? _selectedSymptom;
  DateTime? _selectedReservationDate;
  String? _selectedReservationTime;
  _ServiceBookingStep _currentStep = _ServiceBookingStep.productInfo;
  final _detailedSymptomController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailAddressController = TextEditingController();

  bool get _isVisit => widget.serviceType == ServiceBookingType.visit;
  String get _screenTitle => _isVisit ? '출장 서비스' : '상담 서비스';
  String get _productSectionTitle => _isVisit ? '출장 예약 제품' : '상담 예약 제품';
  String get _scheduleSectionTitle => _isVisit ? '출장 날짜 예약' : '상담 날짜 예약';

  bool get _canProceed {
    switch (_currentStep) {
      case _ServiceBookingStep.productInfo:
        return _selectedProduct != null &&
            _selectedProductType != null &&
            _selectedSymptom != null;
      case _ServiceBookingStep.customerInfo:
        return _nameController.text.trim().isNotEmpty &&
            _phoneController.text.trim().isNotEmpty &&
            _addressController.text.trim().isNotEmpty;
      case _ServiceBookingStep.scheduleInfo:
        return _selectedReservationDate != null &&
            _selectedReservationTime != null;
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialUserName.trim();
    _phoneController.text = widget.initialPhoneNumber.trim();
    _addressController.text = widget.initialAddress.trim();
    unawaited(_prefillUserProfile());
  }

  @override
  void dispose() {
    _detailedSymptomController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _detailAddressController.dispose();
    super.dispose();
  }

  Future<void> _prefillUserProfile() async {
    if (widget.userId <= 0 || widget.baseUrl.trim().isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/users/${widget.userId}'),
      );
      if (response.statusCode != 200) return;
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rawUser = decoded['user'];
      if (rawUser is! Map) return;
      final profile = _ServiceBookingUserProfile.fromJson(
        Map<String, dynamic>.from(rawUser),
      );
      if (!mounted) return;
      setState(() {
        if (_nameController.text.trim().isEmpty ||
            _nameController.text.trim() == widget.initialUserName.trim()) {
          _nameController.text = profile.name;
        }
        if (_phoneController.text.trim().isEmpty) {
          _phoneController.text = profile.phone;
        }
        if (_addressController.text.trim().isEmpty) {
          _addressController.text = profile.address;
        }
      });
    } catch (_) {}
  }

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _firstReservableDate => _today.add(const Duration(days: 1));
  DateTime get _lastReservableDate =>
      _firstReservableDate.add(const Duration(days: 60));

  DateTime get _defaultReservableDate {
    var candidate = _firstReservableDate;
    while (!_isReservableDate(candidate)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  bool _isReservableDate(DateTime date) {
    final normalized = DateUtils.dateOnly(date);
    return !normalized.isBefore(_firstReservableDate) &&
        normalized.weekday != DateTime.sunday;
  }

  Set<String> _unavailableTimeSlotsFor(DateTime date) {
    if (date.weekday == DateTime.saturday) {
      return {'15:00', '16:00', '17:00'};
    }
    return date.day.isEven ? {'11:00', '16:00'} : {'10:00', '15:00'};
  }

  String _formatReservationDate(DateTime date) {
    final normalized = DateUtils.dateOnly(date);
    final year = normalized.year.toString();
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '$year.$month.$day';
  }

  Future<void> _showOptionSheet({
    required String title,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF212121),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontFamily: 'Pretendard',
                ),
              ),
              const SizedBox(height: 12),
              ...options.map(
                (option) => InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onSelected(option);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: const TextStyle(
                              color: Color(0xFF212121),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              fontFamily: 'Pretendard',
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Color(0xFF606C80),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    if (_currentStep == _ServiceBookingStep.productInfo) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _currentStep = _currentStep == _ServiceBookingStep.scheduleInfo
          ? _ServiceBookingStep.customerInfo
          : _ServiceBookingStep.productInfo;
    });
  }

  void _handleAddressSearch() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('주소 검색은 준비 중이에요. 주소를 직접 입력해 주세요.')),
    );
  }

  void _handleNext() {
    if (!_canProceed) return;
    if (_currentStep == _ServiceBookingStep.productInfo) {
      setState(() => _currentStep = _ServiceBookingStep.customerInfo);
      return;
    }
    if (_currentStep == _ServiceBookingStep.customerInfo) {
      setState(() {
        _selectedReservationDate ??= _defaultReservableDate;
        if (_selectedReservationDate != null &&
            _selectedReservationTime != null &&
            _unavailableTimeSlotsFor(
              _selectedReservationDate!,
            ).contains(_selectedReservationTime)) {
          _selectedReservationTime = null;
        }
        _currentStep = _ServiceBookingStep.scheduleInfo;
      });
      return;
    }
    Navigator.of(context).pop(
      ServiceBookingDraft(
        product: _selectedProduct!,
        productType: _selectedProductType!,
        symptom: _selectedSymptom!,
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        detailAddress: _detailAddressController.text.trim(),
        reservationDate: _formatReservationDate(_selectedReservationDate!),
        reservationTime: _selectedReservationTime!,
        detailedSymptom: _detailedSymptomController.text.trim().isEmpty
            ? null
            : _detailedSymptomController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productTypes = _selectedProduct == null
        ? const <String>[]
        : (_productTypeOptions[_selectedProduct!] ?? const <String>[]);
    final symptoms = _selectedProduct == null
        ? const <String>[]
        : (_symptomOptions[_selectedProduct!] ?? const <String>[]);

    final body = switch (_currentStep) {
      _ServiceBookingStep.productInfo => _ServiceBookingProductStep(
        sectionTitle: _productSectionTitle,
        selectedProduct: _selectedProduct,
        selectedProductType: _selectedProductType,
        selectedSymptom: _selectedSymptom,
        detailedSymptomController: _detailedSymptomController,
        onSelectProduct: () => _showOptionSheet(
          title: '제품 선택',
          options: _productOptions,
          onSelected: (value) => setState(() {
            _selectedProduct = value;
            _selectedProductType = null;
            _selectedSymptom = null;
            _detailedSymptomController.clear();
          }),
        ),
        onSelectProductType: productTypes.isEmpty
            ? null
            : () => _showOptionSheet(
                title: '제품 유형 선택',
                options: productTypes,
                onSelected: (value) =>
                    setState(() => _selectedProductType = value),
              ),
        onSelectSymptom: symptoms.isEmpty
            ? null
            : () => _showOptionSheet(
                title: '증상 선택',
                options: symptoms,
                onSelected: (value) => setState(() {
                  _selectedSymptom = value;
                  _detailedSymptomController.clear();
                }),
              ),
      ),
      _ServiceBookingStep.customerInfo => _ServiceBookingCustomerStep(
        nameController: _nameController,
        phoneController: _phoneController,
        addressController: _addressController,
        detailAddressController: _detailAddressController,
        onChanged: (_) => setState(() {}),
        onAddressSearch: _handleAddressSearch,
      ),
      _ServiceBookingStep.scheduleInfo => _ServiceBookingScheduleStep(
        title: _scheduleSectionTitle,
        selectedDate: _selectedReservationDate ?? _defaultReservableDate,
        selectedTime: _selectedReservationTime,
        unavailableSlots: _unavailableTimeSlotsFor(
          _selectedReservationDate ?? _defaultReservableDate,
        ),
        firstDate: _defaultReservableDate,
        lastDate: _lastReservableDate,
        today: _today,
        onDateChanged: (value) => setState(() {
          _selectedReservationDate = DateUtils.dateOnly(value);
          if (_selectedReservationTime != null &&
              _unavailableTimeSlotsFor(
                _selectedReservationDate!,
              ).contains(_selectedReservationTime)) {
            _selectedReservationTime = null;
          }
        }),
        onTimeSelected: (value) =>
            setState(() => _selectedReservationTime = value),
        isReservableDate: _isReservableDate,
      ),
    };

    final nextLabel = _currentStep == _ServiceBookingStep.scheduleInfo
        ? '완료'
        : '다음';

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 10, 19, 0),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 24, height: 24),
                    Expanded(
                      child: Text(
                        _screenTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.11,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(context).maybePop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 24,
                        color: Color(0xFF212121),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(19, 12, 19, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ServiceBookingInfoNotice(),
                    const SizedBox(height: 28),
                    body,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 0, 19, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ServiceBookingBottomButton(
                label: '이전',
                width: 163,
                height: 48,
                backgroundColor: Colors.white.withValues(alpha: 0.7),
                borderColor: const Color(0xFFD3D6D8),
                textColor: const Color(0xFF9CA4AF),
                onTap: _handleBack,
              ),
              const SizedBox(width: 11),
              _ServiceBookingBottomButton(
                label: nextLabel,
                width: 163,
                height: 48,
                backgroundColor: _canProceed
                    ? const Color(0xFF606C80)
                    : const Color(0xFFD3D6D8),
                textColor: Colors.white,
                onTap: _canProceed ? _handleNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceBookingInfoNotice extends StatelessWidget {
  const _ServiceBookingInfoNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF606C80)),
        SizedBox(width: 4),
        Flexible(
          child: Text(
            '현재는 일부 제품만 Chat REBO에서 예약할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF606C80),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.17,
              fontFamily: 'Pretendard',
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceBookingSectionHeader extends StatelessWidget {
  const _ServiceBookingSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.125,
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          '*',
          style: TextStyle(
            color: Color(0xFFEB4C4C),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.125,
            fontFamily: 'Pretendard',
          ),
        ),
      ],
    );
  }
}

class _ServiceBookingProductStep extends StatelessWidget {
  const _ServiceBookingProductStep({
    required this.sectionTitle,
    required this.selectedProduct,
    required this.selectedProductType,
    required this.selectedSymptom,
    required this.detailedSymptomController,
    required this.onSelectProduct,
    required this.onSelectProductType,
    required this.onSelectSymptom,
  });

  final String sectionTitle;
  final String? selectedProduct;
  final String? selectedProductType;
  final String? selectedSymptom;
  final TextEditingController detailedSymptomController;
  final VoidCallback onSelectProduct;
  final VoidCallback? onSelectProductType;
  final VoidCallback? onSelectSymptom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ServiceBookingSectionHeader(sectionTitle),
        const SizedBox(height: 10),
        _ServiceBookingSelectionField(
          label: selectedProduct ?? '어떤 제품에 대해 문의하고 싶으신가요.',
          isPlaceholder: selectedProduct == null,
          onTap: onSelectProduct,
        ),
        const SizedBox(height: 8),
        _ServiceBookingSelectionField(
          label: selectedProductType ?? '어떤 유형의 제품인가요.',
          isPlaceholder: selectedProductType == null,
          onTap: onSelectProductType,
        ),
        const SizedBox(height: 28),
        const _ServiceBookingSectionHeader('자주 묻는 증상'),
        const SizedBox(height: 10),
        _ServiceBookingSelectionField(
          label: selectedSymptom ?? '증상을 선택해 주세요.',
          isPlaceholder: selectedSymptom == null,
          onTap: onSelectSymptom,
        ),
        if (selectedSymptom != null) ...[
          const SizedBox(height: 12),
          const Text(
            '세부 증상 입력',
            style: TextStyle(
              color: Color(0xFF000000),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 70),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD3D6D8)),
            ),
            child: TextField(
              controller: detailedSymptomController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '증상을 자세히 입력해 주세요.',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA4AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ServiceBookingCustomerStep extends StatelessWidget {
  const _ServiceBookingCustomerStep({
    required this.nameController,
    required this.phoneController,
    required this.addressController,
    required this.detailAddressController,
    required this.onChanged,
    required this.onAddressSearch,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController detailAddressController;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddressSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ServiceBookingSectionHeader('이름'),
        const SizedBox(height: 12),
        _ServiceBookingInputField(
          controller: nameController,
          hintText: '이름을 입력해 주세요.',
          fillColor: Colors.white,
          borderColor: const Color(0xFFD3D6D8),
          onChanged: onChanged,
        ),
        const SizedBox(height: 24),
        const _ServiceBookingSectionHeader('휴대전화번호'),
        const SizedBox(height: 12),
        _ServiceBookingInputField(
          controller: phoneController,
          hintText: '휴대전화번호를 입력해 주세요.',
          fillColor: Colors.white,
          borderColor: const Color(0xFFD3D6D8),
          keyboardType: TextInputType.phone,
          onChanged: onChanged,
        ),
        const SizedBox(height: 24),
        const _ServiceBookingSectionHeader('주소'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ServiceBookingInputField(
                controller: addressController,
                hintText: '도로명 주소를 입력해 주세요.',
                fillColor: Colors.white,
                borderColor: const Color(0xFFD3D6D8),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAddressSearch,
              child: Container(
                width: 88,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD3D6D8)),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '주소찾기',
                  style: TextStyle(
                    color: Color(0xFF5D5B5B),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.14,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ServiceBookingInputField(
          controller: detailAddressController,
          hintText: '상세 주소를 입력해 주세요.',
          fillColor: Colors.white,
          borderColor: const Color(0xFFD3D6D8),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ServiceBookingScheduleStep extends StatelessWidget {
  const _ServiceBookingScheduleStep({
    required this.title,
    required this.selectedDate,
    required this.selectedTime,
    required this.unavailableSlots,
    required this.firstDate,
    required this.lastDate,
    required this.today,
    required this.onDateChanged,
    required this.onTimeSelected,
    required this.isReservableDate,
  });

  final String title;
  final DateTime selectedDate;
  final String? selectedTime;
  final Set<String> unavailableSlots;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime today;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onTimeSelected;
  final bool Function(DateTime date) isReservableDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ServiceBookingSectionHeader(title),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD3D6D8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: const Color(0xFF606C80),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: const Color(0xFF212121),
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: selectedDate,
                  firstDate: firstDate,
                  lastDate: lastDate,
                  currentDate: today,
                  selectableDayPredicate: isReservableDate,
                  onDateChanged: onDateChanged,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: const [
                  _ServiceBookingLegendItem(
                    color: Colors.white,
                    borderColor: Color(0xFFD3D6D8),
                    label: '예약가능',
                  ),
                  _ServiceBookingLegendItem(
                    color: Color(0xFFEB4C4C),
                    label: '선택',
                  ),
                  _ServiceBookingLegendItem(
                    color: Color(0xFFE3E6EA),
                    label: '불가',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _ServiceBookingSectionHeader('시간 선택'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final slot in _ServiceBookingFlowScreenState._timeSlotOptions)
              _ServiceBookingTimeChip(
                label: slot,
                isSelected: selectedTime == slot,
                isUnavailable: unavailableSlots.contains(slot),
                onTap: unavailableSlots.contains(slot)
                    ? null
                    : () => onTimeSelected(slot),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '출장 점검료 안내',
                style: TextStyle(
                  color: Color(0xFF212121),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontFamily: 'Pretendard',
                ),
              ),
              SizedBox(height: 12),
              Text(
                '• 챗봇에서는 한 채팅당 1건씩만 예약할 수 있습니다.',
                style: TextStyle(
                  color: Color(0xFF5D5B5B),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                  fontFamily: 'Pretendard',
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• 무상 보증기간이 지난 경우 출장비는 기본 28,000원, 평일 18시 이후 및 토/일/공휴일은 33,000원이 발생하며 점검 내용에 따라 수리비와 부품비가 추가될 수 있습니다.',
                style: TextStyle(
                  color: Color(0xFF5D5B5B),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                  fontFamily: 'Pretendard',
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• 서비스 요금은 카드 또는 현금으로만 결제할 수 있으며, 수리 당일 현장에서 결제해야 수리가 진행됩니다.',
                style: TextStyle(
                  color: Color(0xFF5D5B5B),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceBookingLegendItem extends StatelessWidget {
  const _ServiceBookingLegendItem({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5D5B5B),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.23,
            fontFamily: 'Pretendard',
          ),
        ),
      ],
    );
  }
}

class _ServiceBookingSelectionField extends StatelessWidget {
  const _ServiceBookingSelectionField({
    required this.label,
    required this.isPlaceholder,
    required this.onTap,
  });

  final String label;
  final bool isPlaceholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD3D6D8)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? (isPlaceholder
                            ? const Color(0xFFB8BEC5)
                            : const Color(0xFF212121))
                      : const Color(0xFFD3D6D8),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.14,
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: enabled
                  ? const Color(0xFF606C80)
                  : const Color(0xFFD3D6D8),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceBookingInputField extends StatelessWidget {
  const _ServiceBookingInputField({
    required this.controller,
    required this.hintText,
    required this.fillColor,
    required this.borderColor,
    this.keyboardType = TextInputType.text,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final Color fillColor;
  final Color borderColor;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF5D5B5B),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.14,
          fontFamily: 'Pretendard',
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF9CA4AF),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.14,
            fontFamily: 'Pretendard',
          ),
        ),
      ),
    );
  }
}

class _ServiceBookingTimeChip extends StatelessWidget {
  const _ServiceBookingTimeChip({
    required this.label,
    required this.isSelected,
    required this.isUnavailable,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isUnavailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected
        ? const Color(0xFF606C80)
        : isUnavailable
        ? const Color(0xFFE3E6EA)
        : Colors.white;
    final borderColor = isSelected
        ? const Color(0xFF606C80)
        : const Color(0xFFD3D6D8);
    final textColor = isSelected
        ? Colors.white
        : isUnavailable
        ? const Color(0xFF9CA4AF)
        : const Color(0xFF5D5B5B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.23,
            fontFamily: 'Pretendard',
          ),
        ),
      ),
    );
  }
}

class _ServiceBookingBottomButton extends StatelessWidget {
  const _ServiceBookingBottomButton({
    required this.label,
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final double width;
  final double height;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.125,
            fontFamily: 'Pretendard',
          ),
        ),
      ),
    );
  }
}
