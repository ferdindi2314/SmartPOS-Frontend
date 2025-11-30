import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/product_model.dart';
import '../../../data/models/stock_adjustment_result.dart';
import '../../../data/models/stock_log_model.dart';
import '../../../providers/admin/stock_management_provider.dart';
import '../../widgets/custom_app_bar.dart';
import 'widgets/stock_adjustment_sheet.dart';

class StockAdjustmentPage extends ConsumerStatefulWidget {
  const StockAdjustmentPage({super.key});

  static const String routeName = 'stock-adjustment';
  static const String routePath = '/admin/stocks';

  @override
  ConsumerState<StockAdjustmentPage> createState() =>
      _StockAdjustmentPageState();
}

class _StockAdjustmentPageState extends ConsumerState<StockAdjustmentPage> {
  final _scrollController = ScrollController();
  final _logDateFormat = DateFormat('dd MMM yyyy • HH:mm');
  final _filterDateFormat = DateFormat('dd MMM yyyy');
  ProviderSubscription<StockManagementState>? _subscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _subscription = ref.listenManual<StockManagementState>(
      stockManagementProvider,
      (previous, next) {
        if (!mounted) return;
        final prevMessage = previous?.errorMessage;
        final nextMessage = next.errorMessage;
        if (nextMessage != null && nextMessage != prevMessage) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(nextMessage)));
        }
      },
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _subscription?.close();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      ref.read(stockManagementProvider.notifier).loadMore();
    }
  }

  Future<void> _pickDate() async {
    final current = ref.read(stockManagementProvider).selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await ref.read(stockManagementProvider.notifier).setDate(picked);
  }

  Future<void> _openAdjustmentSheet(bool isStockIn) async {
    final result = await showModalBottomSheet<StockAdjustmentResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockAdjustmentSheet(isStockIn: isStockIn),
    );
    if (result == null || !mounted) return;
    final action = isStockIn ? 'ditambahkan' : 'dikurangi';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Stok ${result.productName} $action. Total sekarang ${result.newStock}.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stockManagementProvider);
    final productOptions = ref.watch(stockProductOptionsProvider);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Penyesuaian Stok',
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () =>
                ref.read(stockManagementProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aksi Stok',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openAdjustmentSheet(true),
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Stok Masuk'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openAdjustmentSheet(false),
                          icon: const Icon(Icons.indeterminate_check_box),
                          label: const Text('Stok Keluar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Filter Log',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FilterSection(
                    state: state,
                    productOptions: productOptions,
                    onClear: () => ref
                        .read(stockManagementProvider.notifier)
                        .clearFilters(),
                    onSelectProduct: (id) => ref
                        .read(stockManagementProvider.notifier)
                        .setProduct(id),
                    onSelectType: (type) => ref
                        .read(stockManagementProvider.notifier)
                        .setType(type),
                    onPickDate: _pickDate,
                    onClearDate: () => ref
                        .read(stockManagementProvider.notifier)
                        .setDate(null),
                    dateLabel: state.selectedDate == null
                        ? 'Semua tanggal'
                        : _filterDateFormat.format(state.selectedDate!),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildLogList(state)),
        ],
      ),
    );
  }

  Widget _buildLogList(StockManagementState state) {
    if (state.isLoading && state.logs.isEmpty) {
      return const _LogSkeleton();
    }
    if (state.errorMessage != null && state.logs.isEmpty) {
      return _ListError(
        message: state.errorMessage!,
        onRetry: () => ref.read(stockManagementProvider.notifier).refresh(),
      );
    }
    if (state.logs.isEmpty) {
      return const _EmptyLogs();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(stockManagementProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: state.logs.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= state.logs.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final log = state.logs[index];
          return _StockLogCard(log: log, logDateFormat: _logDateFormat);
        },
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.state,
    required this.productOptions,
    required this.onSelectProduct,
    required this.onSelectType,
    required this.onPickDate,
    required this.onClear,
    required this.onClearDate,
    required this.dateLabel,
  });

  final StockManagementState state;
  final AsyncValue<List<ProductModel>> productOptions;
  final ValueChanged<int?> onSelectProduct;
  final ValueChanged<String?> onSelectType;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onClear;
  final Future<void> Function() onClearDate;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        productOptions.when(
          data: (items) => DropdownButtonFormField<int?>(
            decoration: const InputDecoration(labelText: 'Produk'),
            value: state.selectedProductId,
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('Semua produk')),
              ...items.map(
                (product) => DropdownMenuItem<int?>(
                  value: product.id,
                  child: Text(product.name),
                ),
              ),
            ],
            onChanged: onSelectProduct,
          ),
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (error, _) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Produk gagal dimuat: $error',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          decoration: const InputDecoration(labelText: 'Jenis penyesuaian'),
          value: state.selectedType,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Semua jenis'),
            ),
            const DropdownMenuItem<String?>(
              value: 'in',
              child: Text('Stok Masuk'),
            ),
            const DropdownMenuItem<String?>(
              value: 'out',
              child: Text('Stok Keluar'),
            ),
          ],
          onChanged: onSelectType,
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Tanggal'),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Pilih tanggal',
                onPressed: () => onPickDate(),
                icon: const Icon(Icons.event),
              ),
              if (state.selectedDate != null)
                IconButton(
                  tooltip: 'Hapus tanggal',
                  onPressed: () => onClearDate(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => onClear(),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Reset filter'),
          ),
        ),
      ],
    );
  }
}

class _StockLogCard extends StatelessWidget {
  const _StockLogCard({required this.log, required this.logDateFormat});

  final StockLogModel log;
  final DateFormat logDateFormat;

  Color _chipColor(BuildContext context) {
    return log.isStockIn ? Colors.green : Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.productName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        log.productBarcode,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(log.typeLabel),
                  backgroundColor: color.withOpacity(.15),
                  labelStyle: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  log.isStockIn ? Icons.trending_up : Icons.trending_down,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  '${log.quantity} pcs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(log.description),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(log.userName, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.schedule, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    logDateFormat.format(log.createdAt),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            const Text('Belum ada log penyesuaian stok'),
            const SizedBox(height: 4),
            Text(
              'Tambahkan stok masuk/keluar untuk melihat riwayat di sini.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListError extends StatelessWidget {
  const _ListError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogSkeleton extends StatelessWidget {
  const _LogSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 4,
    );
  }
}
