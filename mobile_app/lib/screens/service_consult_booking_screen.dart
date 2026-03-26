import 'package:flutter/material.dart';

import 'service_booking_flow_screen.dart';

class ServiceConsultBookingScreen extends StatelessWidget {
  const ServiceConsultBookingScreen({
    super.key,
    required this.baseUrl,
    required this.userId,
    required this.initialUserName,
    required this.initialPhoneNumber,
    required this.initialAddress,
  });

  final String baseUrl;
  final int userId;
  final String initialUserName;
  final String initialPhoneNumber;
  final String initialAddress;

  @override
  Widget build(BuildContext context) {
    return ServiceBookingFlowScreen(
      serviceType: ServiceBookingType.consult,
      baseUrl: baseUrl,
      userId: userId,
      initialUserName: initialUserName,
      initialPhoneNumber: initialPhoneNumber,
      initialAddress: initialAddress,
    );
  }
}
