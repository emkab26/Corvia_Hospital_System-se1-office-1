import 'package:flutter/material.dart';
import '../paramedic/paramedic_workspace_page.dart';

/// Hospital shell entry point; crew can open the workspace from Settings.
class HospitalFleetParamedicPage extends StatelessWidget {
  const HospitalFleetParamedicPage({super.key});
  @override
  Widget build(BuildContext context) => const ParamedicWorkspacePage(
      showAppBar: false, initialSection: 'Vehicles', title: 'Fleet Management');
}
