class PhoneNumberEntry {
  final int id;
  final String? fullName;
  final String number;
  double debt; // comes from external JSON — can change every 5 s
  final String? contractNumber;
  String status; // 'pending' | 'called'
  DateTime? calledAt;
  DateTime? entryDate;
  int callCount;

  PhoneNumberEntry({
    required this.id,
    this.fullName,
    required this.number,
    required this.debt,
    this.contractNumber,
    required this.status,
    this.calledAt,
    this.entryDate,
    this.callCount = 0,
  });

  bool get isCalled => callCount > 0;

  /// Entry disappears from active lists when BOTH are true:
  /// 1. debt has reached 0 (from the external JSON sync)
  /// 2. the worker has called this customer at least once
  bool get isResolved => debt <= 0 && isCalled;

  factory PhoneNumberEntry.fromJson(Map<String, dynamic> json) {
    return PhoneNumberEntry(
      id: json['id'] as int,
      fullName: json['full_name'] as String?,
      number: json['number'] as String,
      debt: double.tryParse('${json['debt'] ?? 0}') ?? 0,
      contractNumber: json['contract_number'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      calledAt: json['called_at'] != null ? DateTime.tryParse(json['called_at']) : null,
      entryDate: json['entry_date'] != null ? DateTime.tryParse(json['entry_date']) : null,
      callCount: int.tryParse('${json['call_count'] ?? 0}') ?? 0,
    );
  }
}

class WorkerSummary {
  final int id;
  final String name;
  final String phone;
  final int pendingCount;
  final int calledCount;
  final double totalDebt;      // sum of all current debts
  final double totalOutstanding; // same as totalDebt (from external source)

  WorkerSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.pendingCount,
    required this.calledCount,
    this.totalDebt = 0,
    this.totalOutstanding = 0,
  });

  factory WorkerSummary.fromJson(Map<String, dynamic> json) {
    return WorkerSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
      pendingCount: int.tryParse('${json['pending_count'] ?? 0}') ?? 0,
      calledCount: int.tryParse('${json['called_count'] ?? 0}') ?? 0,
      totalDebt: double.tryParse('${json['total_debt'] ?? 0}') ?? 0,
      totalOutstanding: double.tryParse('${json['total_outstanding'] ?? 0}') ?? 0,
    );
  }
}
