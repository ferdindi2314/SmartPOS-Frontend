import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category_model.dart';
import '../../../providers/admin/category_management_provider.dart';
import '../../widgets/custom_app_bar.dart';
import 'widgets/category_form_sheet.dart';

class CategoryManagementPage extends ConsumerStatefulWidget {
  const CategoryManagementPage({super.key});

  static const String routeName = 'category-management';
  static const String routePath = '/admin/categories';

  @override
  ConsumerState<CategoryManagementPage> createState() =>
      _CategoryManagementPageState();
}

class _CategoryManagementPageState
    extends ConsumerState<CategoryManagementPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  ProviderSubscription<CategoryManagementState>? _subscription;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(categoryManagementProvider).searchQuery;
    _subscription = ref.listenManual<CategoryManagementState>(
      categoryManagementProvider,
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
    _subscription?.close();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(categoryManagementProvider.notifier).setSearchQuery(value);
    });
  }

  Future<void> _openForm({CategoryModel? category}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CategoryFormSheet(initial: category),
    );
    if (result == true && mounted) {
      final message = category == null
          ? 'Kategori berhasil dibuat'
          : 'Kategori diperbarui';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _confirmDelete(CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Kategori'),
          content: Text(
            'Hapus ${category.name}? Kategori yang memiliki produk tidak dapat dihapus.',
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
          .read(categoryManagementProvider.notifier)
          .deleteCategory(category.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${category.name} dihapus')));
    } catch (_) {
      // error already surfaced
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoryManagementProvider);

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Kelola Kategori',
        showBackButton: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Kategori Baru'),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                return TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Cari kategori',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(categoryManagementProvider.notifier)
                                  .setSearchQuery('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: _onSearchChanged,
                );
              },
            ),
          ),
          Expanded(child: _buildCategoryList(state)),
        ],
      ),
    );
  }

  Widget _buildCategoryList(CategoryManagementState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const _CategoryListSkeleton();
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return _ListError(
        message: state.errorMessage!,
        onRetry: () => ref.read(categoryManagementProvider.notifier).refresh(),
      );
    }
    if (state.isEmpty) {
      return _EmptyCategory(onCreate: () => _openForm());
    }

    final categories = state.filteredItems;
    return RefreshIndicator(
      onRefresh: () => ref.read(categoryManagementProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isBusy = state.busyCategoryIds.contains(category.id);
          return _CategoryCard(
            category: category,
            isBusy: isBusy,
            onEdit: () => _openForm(category: category),
            onDelete: () => _confirmDelete(category),
            onToggleStatus: (value) => ref
                .read(categoryManagementProvider.notifier)
                .toggleCategory(category, value),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleStatus,
  });

  final CategoryModel category;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleStatus;

  @override
  Widget build(BuildContext context) {
    final statusColor = category.isActive ? Colors.green : Colors.red;
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
                        category.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if ((category.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          category.description!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: category.isActive,
                  onChanged: isBusy ? null : onToggleStatus,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  label: Text(category.isActive ? 'Aktif' : 'Nonaktif'),
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

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Belum ada kategori terdaftar'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Kategori'),
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

class _CategoryListSkeleton extends StatelessWidget {
  const _CategoryListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
    );
  }
}
