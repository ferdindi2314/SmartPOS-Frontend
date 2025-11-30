import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../data/models/transaction_history_model.dart';
import '../../../providers/transaction_history_provider.dart';
import '../../../utils/formatters.dart';
import '../../widgets/custom_app_bar.dart';
import '../admin/category_management_page.dart';
import '../admin/product_management_page.dart';
import '../admin/report_overview_page.dart';
import '../admin/stock_adjustment_page.dart';
import '../history/history_page.dart';
import '../start_transaction/start_transaction_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const String routeName = 'dashboard';
  static const String routePath = '/dashboard';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final isAdmin = authState.isAdmin;
    final shortcuts = <_ShortcutConfig>[
      const _ShortcutConfig(
        icon: Icons.point_of_sale,
        label: 'Mulai Transaksi',
        routePath: StartTransactionPage.routePath,
      ),
      const _ShortcutConfig(
        icon: Icons.history,
        label: 'Riwayat',
        routePath: HistoryPage.routePath,
      ),
    ];

    if (isAdmin) {
      shortcuts.addAll(const [
        _ShortcutConfig(
          icon: Icons.inventory_2,
          label: 'Kelola Produk',
          routePath: ProductManagementPage.routePath,
        ),
        _ShortcutConfig(
          icon: Icons.category,
          label: 'Kategori Produk',
          routePath: CategoryManagementPage.routePath,
        ),
        _ShortcutConfig(
          icon: Icons.warehouse,
          label: 'Penyesuaian Stok',
          routePath: StockAdjustmentPage.routePath,
        ),
        _ShortcutConfig(
          icon: Icons.query_stats,
          label: 'Laporan Penjualan',
          routePath: ReportOverviewPage.routePath,
        ),
      ]);
    }
    final todaySummary = ref.watch(transactionTodaySummaryProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Dashboard'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(
                    userName: user?.name ?? '-',
                    roleLabel: authState.roleLabel,
                  ),
                  const SizedBox(height: 16),
                  todaySummary.when(
                    data: (summary) => _TodaySummaryCard(summary: summary),
                    loading: () => const _TodaySummarySkeleton(),
                    error: (error, _) => _TodaySummaryError(
                      message: '$error',
                      onRetry: () => ref
                          .read(transactionTodaySummaryProvider.notifier)
                          .refresh(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Shortcut',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.2,
                        ),
                    itemCount: shortcuts.length,
                    itemBuilder: (context, index) {
                      final shortcut = shortcuts[index];
                      return _ShortcutButton(
                        icon: shortcut.icon,
                        label: shortcut.label,
                        onTap: () => context.push(shortcut.routePath),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.userName, required this.roleLabel});

  final String userName;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33247CFF),
            offset: Offset(0, 12),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kasir Aktif',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            userName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            roleLabel.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({required this.summary});

  final TransactionTodaySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Transaksi Hari Ini',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${summary.totalTransactions}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Omzet', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text(
                  formatCurrency(summary.totalAmount),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummarySkeleton extends StatelessWidget {
  const _TodaySummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [_SkeletonBox(width: 80), _SkeletonBox(width: 140)],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _TodaySummaryError extends StatelessWidget {
  const _TodaySummaryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Create a more user-friendly message
    String displayMessage = message;
    if (message.contains('404') || message.contains('Not Found')) {
      displayMessage =
          'Data ringkasan tidak tersedia. Hubungi administrator jika masalah berlanjut.';
    } else if (message.contains('Connection')) {
      displayMessage =
          'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
    } else if (message.contains('timeout')) {
      displayMessage = 'Permintaan terlalu lama. Silakan coba lagi.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: Colors.amber.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayMessage,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.amber.shade700),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primaryBlue, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutConfig {
  const _ShortcutConfig({
    required this.icon,
    required this.label,
    required this.routePath,
  });

  final IconData icon;
  final String label;
  final String routePath;
}
