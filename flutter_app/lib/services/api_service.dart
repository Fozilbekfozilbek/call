import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../models/phone_number.dart';

class ApiService {
  final String token;
  ApiService(this.token);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  // ─── Admin: workers ───────────────────────────────────────────────────────

  Future<List<WorkerSummary>> fetchWorkers() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/admin/workers'),
      headers: _headers,
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Ishchilarni olishda xato');
    return (body['workers'] as List).map((w) => WorkerSummary.fromJson(w)).toList();
  }

  Future<List<PhoneNumberEntry>> fetchWorkerNumbers(int workerId, {DateTime? date}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/admin/workers/$workerId/numbers')
        .replace(queryParameters: date != null ? {'date': _dateFmt.format(date)} : null);
    final res = await http.get(uri, headers: _headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Raqamlarni olishda xato');
    return (body['numbers'] as List).map((n) => PhoneNumberEntry.fromJson(n)).toList();
  }

  Future<int> uploadExcel({
    required int workerId,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/admin/workers/$workerId/upload-excel');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['error'] ?? 'Excel yuklashda xato');
    return (body['numbers'] as List).length;
  }

  Future<void> addNumberManually({
    required int workerId,
    String? fullName,
    required String number,
    required DateTime entryDate,
    String? contractNumber,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/admin/workers/$workerId/numbers'),
      headers: _headers,
      body: jsonEncode({
        'fullName': fullName,
        'number': number,
        'debt': 0, // debt comes from external JSON, not entered manually
        'entryDate': _dateFmt.format(entryDate),
        'contractNumber': contractNumber,
      }),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['error'] ?? 'Raqam qo\'shishda xato');
  }

  Future<List<DateTime>> fetchCallLogs(int workerId, int numberId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/admin/workers/$workerId/numbers/$numberId/call-logs'),
      headers: _headers,
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Tarixni olishda xato');
    return (body['logs'] as List)
        .map((l) => DateTime.parse(l['called_at'] as String))
        .toList();
  }

  Future<String> fetchDebtSourceUrl() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/admin/settings/debt-source-url'),
      headers: _headers,
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'URL olishda xato');
    return (body['url'] as String?) ?? '';
  }

  Future<void> saveDebtSourceUrl(String url) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/admin/settings/debt-source-url'),
      headers: _headers,
      body: jsonEncode({'url': url}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'URL saqlashda xato');
  }

  // ─── Worker ───────────────────────────────────────────────────────────────

  Future<List<PhoneNumberEntry>> fetchMyNumbers({DateTime? date}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/worker/numbers')
        .replace(queryParameters: date != null ? {'date': _dateFmt.format(date)} : null);
    final res = await http.get(uri, headers: _headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Raqamlarni olishda xato');
    return (body['numbers'] as List).map((n) => PhoneNumberEntry.fromJson(n)).toList();
  }

  /// Logs a call. Can be called any number of times. Returns updated entry.
  Future<PhoneNumberEntry> markCalled(int numberId) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/worker/numbers/$numberId/mark-called'),
      headers: _headers,
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Holatni yangilashda xato');
    return PhoneNumberEntry.fromJson(body['number']);
  }

  /// Worker changes which date this customer belongs to.
  Future<PhoneNumberEntry> changeEntryDate(int numberId, DateTime newDate) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/worker/numbers/$numberId/change-date'),
      headers: _headers,
      body: jsonEncode({'entryDate': _dateFmt.format(newDate)}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Sanani yangilashda xato');
    return PhoneNumberEntry.fromJson(body['number']);
  }
}
