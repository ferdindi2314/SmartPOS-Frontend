// StartTransactionPage (fixed cart issue)
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/colors.dart';
import '../../../data/exceptions/app_exception.dart';
import '../../../data/models/product_model.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../providers/category_provider.dart';
import '../../../providers/admin/product_management_provider.dart';
import '../../widgets/custom_app_bar.dart';
import '../payment/payment_page.dart';
import '../scanner/scanner_page.dart';
import '../../../utils/formatters.dart';

class StartTransactionPage extends ConsumerStatefulWidget {
  const StartTransactionPage({super.key});

  static const String routeName = 'startTransaction';
  static const String routePath = '/transaction/start';

  @override
  ConsumerState<StartTransactionPage> createState() =>
      _StartTransactionPageState();
}

class _StartTransactionPageState extends ConsumerState<StartTransactionPage> {
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  String? _lastLookup;
  ProviderSubscription<AsyncValue<ProductModel?>>? _barcodeSubscription;

  // selected category for filtering cart-list display (nullable = all)
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _barcodeSubscription = ref.listenManual<AsyncValue<ProductModel?>>(
      productBarcodeProvider,
      (previous, next) {
        next.whenOrNull(
          data: (product) {
            if (product != null) {
              _barcodeController.clear();
              _lastLookup = null;
              // DEBUG
              print('Barcode lookup found: ${product.name}');
            }
          },
          error: (error, _) => _handleLookupError(error),
        );
      },
    );

    // Load products when page starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(productManagementProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _barcodeSubscription?.close();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  // Function to validate stock before checkout
  bool _validateStock(CartState cart) {
    for (final item in cart.items) {
      final product = item.product;
      final quantity = _getQuantityFromCartItem(item);

      if (quantity > product.stock) {
        _showStockAlert(product.name, product.stock, quantity);
        return false;
      }
    }
    return true;
  }

  // Show stock alert dialog
  void _showStockAlert(String productName, int stock, int quantity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stok Tidak Cukup'),
        content: Text(
          'Pembelian "$productName" melebihi stok!\n\n'
          'Stok tersedia: $stock pcs\n'
          'Jumlah dibeli: $quantity pcs\n\n'
          'Silakan kurangi jumlah pembelian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final barcodeAsync = ref.watch(productBarcodeProvider);
    final categoriesAsync = ref.watch(categoryListProvider);

    // DEBUG: Print semua item di cart
    print('=== DEBUG CART ===');
    print('Total items in cart: ${cart.items.length}');
    for (var i = 0; i < cart.items.length; i++) {
      final item = cart.items[i];
      final quantity = _getQuantityFromCartItem(item);
      print('Item $i: ${item.product.name} - Qty: $quantity');
    }
    print('==================');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baris pertama: Judul utama
            const Text(
              'Transaksi Baru',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Baris kedua: Informasi item dan total
            Text(
              'Item: ${cart.totalItems} - Total: Rp ${formatCurrency(cart.total)}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
        actions: [
          // Tombol Bayar di kanan atas
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: cart.items.isEmpty
                    ? Colors.grey
                    : AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              onPressed: cart.items.isEmpty
                  ? null
                  : () {
                      if (_validateStock(cart)) {
                        context.push(PaymentPage.routePath);
                      }
                    },
              child: const Text(
                'Bayar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- INPUT SECTION (Fixed at top) ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barcodeController,
                        focusNode: _barcodeFocusNode,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Masukkan / scan barcode atau nama produk',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          // Real-time search as user types
                          setState(() {});
                        },
                        onSubmitted: _lookupBarcode,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await context.push<String>(
                          ScannerPage.routePath,
                        );
                        if (result != null && result.isNotEmpty) {
                          _lookupBarcode(result);
                        }
                      },
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Scan'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // --- CATEGORY DROPDOWN ---
                categoriesAsync.when(
                  data: (items) {
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
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: dropdownItems,
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
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
              ],
            ),
          ),

          const SizedBox(height: 8),

          // --- LOOKUP RESULT (Appears below search when found) ---
          if (barcodeAsync.value != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                tileColor: AppColors.lightGray.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(barcodeAsync.value!.name),
                subtitle: Text(
                  'Rp ${barcodeAsync.value!.price.toStringAsFixed(0)}',
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.add_circle,
                    color: AppColors.primaryBlue,
                  ),
                  onPressed: () {
                    final product = barcodeAsync.value!;
                    final currentQuantity = _getCurrentQuantityInCart(
                      cart,
                      product.id,
                    );

                    if (currentQuantity >= product.stock) {
                      _showStockAlert(
                        product.name,
                        product.stock,
                        currentQuantity + 1,
                      );
                    } else {
                      print('Adding product from barcode: ${product.name}');
                      ref.read(cartProvider.notifier).addProduct(product);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // --- CART ITEMS (Always visible at top) ---
          if (cart.items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Item dalam Keranjang (${cart.items.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: cart.items.length > 2 ? 2 : 1,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cart.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = cart.items[index];
                  return _CartProductCard(
                    cartItem: item,
                    onIncrement: () {
                      final product = item.product;
                      final currentQuantity = _getQuantityFromCartItem(item);

                      if (currentQuantity >= product.stock) {
                        _showStockAlert(
                          product.name,
                          product.stock,
                          currentQuantity + 1,
                        );
                      } else {
                        print('Incrementing product: ${product.name}');
                        ref
                            .read(cartProvider.notifier)
                            .incrementItem(product.id);
                      }
                    },
                    onDecrement: () {
                      print('Decrementing product: ${item.product.name}');
                      ref
                          .read(cartProvider.notifier)
                          .decrementItem(item.product.id);
                    },
                    onRemove: () {
                      print('Removing product: ${item.product.name}');
                      ref
                          .read(cartProvider.notifier)
                          .removeItem(item.product.id);
                    },
                  );
                },
              ),
            ),
          ],

          // --- PRODUCT LIST (Scrollable below cart) ---
          Expanded(child: _buildProductListSection(ref, cart)),
        ],
      ),
      bottomNavigationBar: _CheckoutSummary(
        totalItems: cart.totalItems,
        totalAmount: cart.total,
        disabled: cart.items.isEmpty,
        onCheckout: () {
          if (_validateStock(cart)) {
            context.push(PaymentPage.routePath);
          }
        },
      ),
    );
  }

  Widget _buildProductListSection(WidgetRef ref, CartState cart) {
    final state = ref.watch(productManagementProvider);
    final selectedCategoryId = _selectedCategoryId;
    final searchQuery = _barcodeController.text.trim();

    // Handle loading state
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Handle error state
    if (state.errorMessage != null && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Gagal memuat produk: ${state.errorMessage}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.red),
          ),
        ),
      );
    }

    // Filter products by selected category, active status, and search query
    final filteredProducts = state.items.where((product) {
      final categoryMatch =
          selectedCategoryId == null ||
          product.categoryId == selectedCategoryId;
      final activeMatch = product.isActive;
      final searchMatch =
          searchQuery.isEmpty ||
          product.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (product.barcode.toLowerCase().contains(searchQuery.toLowerCase()));
      return categoryMatch && activeMatch && searchMatch;
    }).toList();

    if (filteredProducts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Produk tidak ditemukan'),
            Text(
              'Coba kata kunci lain atau kategori berbeda',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Daftar Produk (${filteredProducts.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: filteredProducts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final product = filteredProducts[index];
              // Find current quantity in cart for this product
              final quantity = _getCurrentQuantityInCart(cart, product.id);

              return _ProductListCard(
                product: product,
                quantity: quantity,
                onIncrement: () {
                  if (quantity >= product.stock) {
                    _showStockAlert(product.name, product.stock, quantity + 1);
                  } else {
                    print('Adding product from list: ${product.name}');
                    ref.read(cartProvider.notifier).addProduct(product);
                  }
                },
                onDecrement: () {
                  if (quantity > 1) {
                    print('Decrementing product from list: ${product.name}');
                    ref.read(cartProvider.notifier).decrementItem(product.id);
                  } else {
                    print('Removing product from list: ${product.name}');
                    ref.read(cartProvider.notifier).removeItem(product.id);
                  }
                },
                onAdd: () {
                  if (quantity >= product.stock) {
                    _showStockAlert(product.name, product.stock, quantity + 1);
                  } else {
                    print(
                      'Adding product from list (add button): ${product.name}',
                    );
                    ref.read(cartProvider.notifier).addProduct(product);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Helper method to get quantity from cart item
  int _getQuantityFromCartItem(dynamic cartItem) {
    if (cartItem == null) return 0;

    // Try common quantity property names
    if (cartItem.quantity != null) return cartItem.quantity;
    if (cartItem.qty != null) return cartItem.qty;
    if (cartItem.count != null) return cartItem.count;
    if (cartItem.amount != null) return cartItem.amount;

    return 0;
  }

  // Helper method to get current quantity of a product in cart
  int _getCurrentQuantityInCart(CartState cart, int productId) {
    try {
      final cartItem = cart.items.firstWhere(
        (item) => item.product.id == productId,
      );
      return _getQuantityFromCartItem(cartItem);
    } catch (e) {
      return 0;
    }
  }

  void _lookupBarcode(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _lastLookup = trimmed;
    print('Looking up barcode: $trimmed');
    ref.read(productBarcodeProvider.notifier).lookup(trimmed);
  }

  void _handleLookupError(Object error) {
    final message = _errorMessage(error);
    if (!mounted) return;
    if (error is BarcodeNotFoundException) {
      _showBarcodeNotFoundDialog(message);
    } else {
      _showErrorSnackBar(message);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _showBarcodeNotFoundDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Produk tidak ditemukan'),
        content: Text('$message\nInput manual barcode atau nama produk?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _barcodeFocusNode.requestFocus();
              _barcodeController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _barcodeController.text.length,
              );
            },
            child: const Text('Input Manual'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _barcodeController.clear();
              _barcodeFocusNode.requestFocus();
            },
            child: const Text('Scan Ulang'),
          ),
        ],
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is AppException) return error.message;
    if (error is DioException) {
      return error.message ?? 'Terjadi kesalahan, coba beberapa saat lagi.';
    }
    return 'Terjadi kesalahan, coba beberapa saat lagi.';
  }
}

// UPDATED: Product card for vertical list
class _ProductListCard extends StatelessWidget {
  const _ProductListCard({
    required this.product,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAdd,
  });

  final ProductModel product;
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Barcode: ${product.barcode}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (product.categoryName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Kategori: ${product.categoryName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Rp ${product.sellPrice.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Stok: ${product.stock} pcs',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Quantity controls or Add button
            if (quantity > 0)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onDecrement,
                      icon: const Icon(Icons.remove, size: 18),
                      padding: const EdgeInsets.all(4),
                    ),
                    Text(
                      '$quantity',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: onIncrement,
                      icon: const Icon(Icons.add, size: 18),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              )
            else
              FilledButton(onPressed: onAdd, child: const Text('Tambah')),
          ],
        ),
      ),
    );
  }
}

// Compact card to display cart item
class _CartProductCard extends StatelessWidget {
  const _CartProductCard({
    required this.cartItem,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final dynamic cartItem;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ProductModel product = cartItem.product;
    final int quantity = _getQuantityFromCartItem(cartItem);
    final double subtotal = cartItem.subtotal;

    return Card(
      elevation: 2,
      color: AppColors.lightGray.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rp ${product.sellPrice.toStringAsFixed(0)} × $quantity',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Stok: ${product.stock} pcs',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: quantity > product.stock
                          ? Colors.red
                          : Colors.grey.shade600,
                      fontWeight: quantity > product.stock
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            // Quantity controls and subtotal
            Row(
              children: [
                // Quantity controls
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onDecrement,
                        icon: const Icon(Icons.remove, size: 16),
                        padding: const EdgeInsets.all(4),
                      ),
                      Text(
                        '$quantity',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: quantity > product.stock
                              ? Colors.red
                              : Colors.black,
                        ),
                      ),
                      IconButton(
                        onPressed: onIncrement,
                        icon: const Icon(Icons.add, size: 16),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Subtotal and remove
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rp ${subtotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Helper function to get quantity from cart item
int _getQuantityFromCartItem(dynamic cartItem) {
  if (cartItem == null) return 0;

  // Try common quantity property names
  if (cartItem.quantity != null) return cartItem.quantity;
  if (cartItem.qty != null) return cartItem.qty;
  if (cartItem.count != null) return cartItem.count;
  if (cartItem.amount != null) return cartItem.amount;

  return 0;
}

class _CheckoutSummary extends StatelessWidget {
  const _CheckoutSummary({
    required this.totalItems,
    required this.totalAmount,
    required this.disabled,
    required this.onCheckout,
  });

  final int totalItems;
  final double totalAmount;
  final bool disabled;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Item',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    '$totalItems pcs',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Belanja',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    'Rp ${totalAmount.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: disabled ? null : onCheckout,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Lanjut ke Pembayaran'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LookupErrorMessage extends StatelessWidget {
  const _LookupErrorMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.red.shade700),
            ),
          ),
          if (onRetry != null)
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
