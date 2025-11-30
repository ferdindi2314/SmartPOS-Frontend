import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category_model.dart';
import '../../../data/models/product_model.dart';
import '../../../providers/admin/product_management_provider.dart';
import '../../../providers/category_provider.dart';
import '../../../utils/formatters.dart';
import '../../widgets/custom_app_bar.dart';
import 'widgets/product_form_sheet.dart';

class ProductManagementPage extends ConsumerStatefulWidget {
  const ProductManagementPage({super.key});

  static const String routeName = 'product-management';
  static const String routePath = '/admin/products';

  @override
  ConsumerState<ProductManagementPage> createState() =>
      _ProductManagementPageState();
}

class _ProductManagementPageState extends ConsumerState<ProductManagementPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  ProviderSubscription<ProductManagementState>? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(productManagementProvider).searchQuery;
    _stateSubscription = ref.listenManual<ProductManagementState>(
      productManagementProvider,
      (previous, next) {
        if (!mounted) return;
        if (next.errorMessage != null &&
            next.errorMessage != previous?.errorMessage) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
        }
        if (next.searchQuery != previous?.searchQuery &&
            next.searchQuery != _searchController.text) {
          _searchController.text = next.searchQuery;
        }
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _stateSubscription?.close();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(productManagementProvider.notifier).setSearch(value.trim());
    });
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    await ref.read(productManagementProvider.notifier).clearFilters();
  }

  Future<void> _openForm({ProductModel? product}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductFormSheet(initial: product),
    );
    if (result == true && mounted) {
      final message = product == null
          ? 'Produk berhasil dibuat'
          : 'Produk diperbarui';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Produk'),
          content: Text(
            'Yakin ingin menghapus ${product.name}? Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(productManagementProvider.notifier)
          .deleteProduct(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${product.name} dihapus')));
    } catch (_) {
      // Error already surfaced via listener.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productManagementProvider);
    final categories = ref.watch(categoryListProvider);

    final hasFilters = state.searchQuery.isNotEmpty || state.categoryId != null;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Kelola Produk', showBackButton: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Produk Baru'),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          _FilterCard(
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            categories: categories,
            selectedCategoryId: state.categoryId,
            onCategoryChanged: (value) =>
                ref.read(productManagementProvider.notifier).setCategory(value),
            onClearFilters: hasFilters ? () => _clearFilters() : null,
          ),
          Expanded(child: _buildProductSection(state)),
        ],
      ),
    );
  }

  Widget _buildProductSection(ProductManagementState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const _ProductListSkeleton();
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return _ListError(
        message: state.errorMessage!,
        onRetry: () => ref.read(productManagementProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return _EmptyProducts(onCreate: () => _openForm());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 120 &&
            state.hasMore &&
            !state.isLoadingMore &&
            !state.isLoading) {
          ref.read(productManagementProvider.notifier).loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => ref.read(productManagementProvider.notifier).refresh(),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final product = state.items[index];
            final isBusy = state.busyProductIds.contains(product.id);
            return _ProductCard(
              product: product,
              isBusy: isBusy,
              onEdit: () => _openForm(product: product),
              onDelete: () => _confirmDelete(product),
              onToggleStatus: (value) => ref
                  .read(productManagementProvider.notifier)
                  .toggleProductStatus(product, value),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.searchController,
    required this.onSearchChanged,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    this.onClearFilters,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final AsyncValue<List<CategoryModel>> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategoryChanged;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                return TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'Cari nama atau barcode',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Kosongkan',
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: onSearchChanged,
                );
              },
            ),
            const SizedBox(height: 12),
            categories.when(
              data: (items) {
                final validValue =
                    selectedCategoryId != null &&
                        items.any(
                          (category) => category.id == selectedCategoryId,
                        )
                    ? selectedCategoryId
                    : null;
                final dropdownItems = items
                    .map(
                      (category) => DropdownMenuItem<int?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList();
                dropdownItems.insert(
                  0,
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Semua kategori'),
                  ),
                );
                return DropdownButtonFormField<int?>(
                  value: validValue,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: dropdownItems,
                  onChanged: onCategoryChanged,
                );
              },
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Text(
                'Kategori gagal dimuat: $error',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ),
            if (onClearFilters != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Reset filter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  final ProductModel product;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final statusColor = product.isActive ? Colors.green : Colors.red;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        product.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Barcode: ${product.barcode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (product.categoryName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Kategori: ${product.categoryName}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: product.isActive,
                  onChanged: isBusy ? null : onToggleStatus,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Harga Jual'),
                    Text(
                      formatCurrency(product.sellPrice),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Stok Saat Ini'),
                    Text('${product.stock} pcs'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  label: Text(product.isActive ? 'Aktif' : 'Nonaktif'),
                  backgroundColor: statusColor.withOpacity(.12),
                  labelStyle: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: isBusy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  onPressed: isBusy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.onCreate});

  final VoidCallback onCreate;

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
            const Text(
              'Belum ada produk yang ditampilkan',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Produk'),
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

class _ProductListSkeleton extends StatelessWidget {
  const _ProductListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
    );
  }
}
