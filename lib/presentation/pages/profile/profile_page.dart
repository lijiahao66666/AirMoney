import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/auth_service.dart';
import '../../providers/points_provider.dart';
import '../auth/login_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PointsCard(),
          const SizedBox(height: 24),
          if (AuthService.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text('${AuthService.phone}'),
              subtitle: const Text('已登录'),
            )
          else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('登录'),
              subtitle: const Text('登录可获赠积分，跨设备同步'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          if (AuthService.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定退出？积分将保留在账户中。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await AuthService.logout();
                  context.read<PointsProvider>().setBalance(0);
                }
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('闹钟提醒'),
            subtitle: const Text('默认 13:00、20:00'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('闹钟设置即将支持')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('分类管理'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('分类管理即将支持')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('哎呀，钱！v1.0 - 少花点，存多点'),
          ),
        ],
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<PointsProvider>(
      builder: (context, pp, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet, size: 48, color: AppColors.primaryGreen),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('积分钱包', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '余额：${NumberFormat('#,###').format(pp.balance)}',
                      style: const TextStyle(fontSize: 20, color: AppColors.pointsGold),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: pp.syncing ? null : () => pp.syncFromServer(),
                icon: pp.syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                label: const Text('同步'),
              ),
            ],
          ),
        );
      },
    );
  }
}
