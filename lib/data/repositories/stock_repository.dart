import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stock_adjustment_payload.dart';
import '../models/stock_adjustment_result.dart';
import '../models/stock_log_model.dart';
import '../services/api_client.dart';

class StockRepository {
  StockRepository(this._dio);

  final Dio _dio;

  Future<StockLogResponse> fetchLogs({
    int page = 1,
    int perPage = 15,
    int? productId,
    String? type,
    String? date,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/stocks/logs',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        if (productId != null) 'product_id': productId,
        if (type != null && type.isNotEmpty) 'type': type,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    return StockLogResponse.fromJson(data);
  }

  Future<StockAdjustmentResult> stockIn(StockAdjustmentPayload payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/stocks/in',
      data: payload.toJson(),
    );
    final body = response.data?['data'] as Map<String, dynamic>? ?? {};
    return StockAdjustmentResult.fromJson(body);
  }

  Future<StockAdjustmentResult> stockOut(StockAdjustmentPayload payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/stocks/out',
      data: payload.toJson(),
    );
    final body = response.data?['data'] as Map<String, dynamic>? ?? {};
    return StockAdjustmentResult.fromJson(body);
  }
}

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  final dio = ref.watch(apiClientProvider);
  return StockRepository(dio);
});
