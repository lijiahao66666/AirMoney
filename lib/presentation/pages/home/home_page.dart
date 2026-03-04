import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../tab_home/tab_home_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().loadRecentBills();
      context.read<PointsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const TabHomePage();
  }
}

