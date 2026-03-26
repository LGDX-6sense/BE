import 'package:flutter/material.dart';

import 'service_booking_flow_screen.dart';

class VisitServiceBookingScreen extends StatelessWidget {
  const VisitServiceBookingScreen({
    super.key,
    required this.baseUrl,
    required this.userId,
    required this.initialUserName,
    required this.initialPhoneNumber,
    required this.initialAddress,
    this.initialProduct,
    this.initialProductType,
    this.initialSymptomCategory,
    this.initialDetailedSymptom,
  });

  final String baseUrl;
  final int userId;
  final String initialUserName;
  final String initialPhoneNumber;
  final String initialAddress;
  final String? initialProduct;
  final String? initialProductType;
  final String? initialSymptomCategory;
  final String? initialDetailedSymptom;

  @override
  Widget build(BuildContext context) {
    return ServiceBookingFlowScreen(
      serviceType: ServiceBookingType.visit,
      baseUrl: baseUrl,
      userId: userId,
      initialUserName: initialUserName,
      initialPhoneNumber: initialPhoneNumber,
      initialAddress: initialAddress,
      initialProduct: initialProduct,
      initialProductType: initialProductType,
      initialSymptomCategory: initialSymptomCategory,
      initialDetailedSymptom: initialDetailedSymptom,
    );
  }
}
