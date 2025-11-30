import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/models/transaction_payload.dart';
import '../data/repositories/transaction_repository.dart';
import '../utils/hive_boxes.dart';

class OfflineQueueState {
  const OfflineQueueState({
    this.pending = 0,
    this.isSyncing = false,
    this.lastError,
  });

  final int pending;
  final bool isSyncing;
  final String? lastError;

  OfflineQueueState copyWith({
    int? pending,
    bool? isSyncing,
    String? lastError,
    bool resetError = false,
  }) {
    return OfflineQueueState(
      pending: pending ?? this.pending,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: resetError ? null : (lastError ?? this.lastError),
    );
  }
}

class OfflineQueueNotifier extends StateNotifier<OfflineQueueState> {
  OfflineQueueNotifier(Ref ref)
    : _box = Hive.box(HiveBoxes.offlineTransactions),
      _repository = ref.read(transactionRepositoryProvider),
      _connectivity = Connectivity(),
      super(
        OfflineQueueState(
          pending: Hive.box(HiveBoxes.offlineTransactions).length,
        ),
      );

  final Box _box;
  final TransactionRepository _repository;
  final Connectivity _connectivity;
  StreamSubscription<dynamic>? _subscription;

  void initialize() {
    _subscription ??= _connectivity.onConnectivityChanged.listen((
      dynamic event,
    ) {
      ConnectivityResult result;
      if (event is ConnectivityResult) {
        result = event;
      } else if (event is List<ConnectivityResult>) {
        result = event.isNotEmpty ? event.first : ConnectivityResult.none;
      } else {
        result = ConnectivityResult.none;
      }
      if (result != ConnectivityResult.none) {
        retryPending();
      }
    });
  }

  Future<void> disposeNotifier() async {
    await _subscription?.cancel();
  }

  Future<void> enqueue(TransactionPayload payload) async {
    await _box.put(payload.localId, jsonEncode(payload.toJson()));
    state = state.copyWith(pending: _box.length);
  }

  Future<void> retryPending() async {
    if (state.isSyncing || _box.isEmpty) return;
    state = state.copyWith(isSyncing: true, resetError: true);

    try {
      final entries = _box.toMap().entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));

      for (final entry in entries) {
        final payloadMap =
            jsonDecode(entry.value as String) as Map<String, dynamic>;
        await _repository.submitJson(payloadMap);
        await _box.delete(entry.key);
      }

      state = state.copyWith(
        pending: _box.length,
        isSyncing: false,
        resetError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isSyncing: false,
        pending: _box.length,
        lastError: 'Sync gagal: $error',
      );
    }
  }
}

final offlineQueueProvider =
    StateNotifierProvider<OfflineQueueNotifier, OfflineQueueState>((ref) {
      final notifier = OfflineQueueNotifier(ref);
      notifier.initialize();
      ref.onDispose(() => notifier.disposeNotifier());
      notifier.retryPending();
      return notifier;
    });
