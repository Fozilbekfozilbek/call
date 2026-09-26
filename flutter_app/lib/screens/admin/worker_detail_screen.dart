import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/phone_number.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';

class WorkerDetailScreen extends StatefulWidget {
  final String token;
  final WorkerSummary worker;
  const WorkerDetailScreen(
      {super.key, required this.token, required this.worker});

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  late final ApiService _api = ApiService(widget.token);
  final _socket = SocketService();
  final _moneyFmt = NumberFormat.decimalPattern('uz');
  final _dateFmt = DateFormat('dd.MM.yyyy');

  List<PhoneNumberEntry> _all = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _load();
    _socket.connectAsAdmin();
    _socket.onNumberCalled((d) { if (d['workerId'] == widget.worker.id) _load(); });
    _socket.onPaymentCollected((d) { if (d['workerId'] == widget.worker.id) _load(); });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<PhoneNumberEntry> get _visible {
    Iterable<PhoneNumberEntry> r = _all;
    if (_filterDate != null) {
      r = r.where((n) => n.entryDate != null && _sameDay(n.entryDate!, _filterDate!));
    }
    return r.toList();
  }

  // Stats from the full (unfiltered) list so the admin always sees totals.
  int get _calledCount => _all.where((n) => n.isCalled).length;
  int get _pendingCount => _all.where((n) => !n.isCalled).length;
  double get _totalDebt => _all.fold(0.0, (s, n) => s + n.debt);

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      setState(() => _all = await _api.fetchWorkerNumbers(widget.worker.id));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      helpText: 'Sana bo\'yicha filter',
      cancelText: 'Bekor', confirmText: 'OK',
    );
    if (p != null) setState(() => _filterDate = p);
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faylni o\'qib bo\'lmadi.')));
      return;
    }
    setState(() => _uploading = true);
    try {
      final count = await _api.uploadExcel(
          workerId: widget.worker.id, bytes: bytes, filename: picked.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count ta raqam yuklandi.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openAddDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final contractCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    DateTime selDate = _filterDate ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setS(() => saving = true);
            try {
              await _api.addNumberManually(
                workerId: widget.worker.id,
                fullName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                number: phoneCtrl.text.trim(),
                entryDate: selDate,
                contractNumber: contractCtrl.text.trim().isEmpty
                    ? null : contractCtrl.text.trim(),
              );
              if (!dCtx.mounted) return;
              Navigator.of(dCtx).pop();
              _load();
            } catch (e) {
              setS(() => saving = false);
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(
                      e.toString().replaceFirst('Exception: ', ''))));
            }
          }

          return AlertDialog(
            title: const Text('Qo\'lda raqam qo\'shish'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Ism Familya (ixtiyoriy)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Telefon raqami *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Majburiy' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: contractCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Shartnoma raqami (ixtiyoriy)'),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: selDate,
                        firstDate: DateTime(2020), lastDate: DateTime(2100),
                        cancelText: 'Bekor', confirmText: 'OK',
                      );
                      if (p != null) setS(() => selDate = p);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Sana',
                          prefixIcon: Icon(Icons.calendar_today, size: 18)),
                      child: Text(_dateFmt.format(selDate)),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dCtx).pop(),
                child: const Text('Bekor'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: saving
                    ? const SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Qo\'shish'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCallHistory(PhoneNumberEntry entry) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(
          entry.fullName != null && entry.fullName!.isNotEmpty
              ? entry.fullName! : 'Qo\'ng\'iroqlar tarixi',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<DateTime>>(
            future: _api.fetchCallLogs(widget.worker.id, entry.id),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text(snap.error.toString()
                    .replaceFirst('Exception: ', ''));
              }
              final logs = snap.data ?? [];
              if (logs.isEmpty) {
                return const Text('Hali qo\'ng\'iroq tarixi yo\'q.');
              }
              final fullFmt = DateFormat('dd.MM.yyyy — HH:mm');
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone_forwarded,
                        size: 18, color: Colors.green),
                    title: Text(fullFmt.format(logs[i])),
                    trailing: Text('#${logs.length - i}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _socket.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.worker.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(
                child: ActionChip(
                  avatar: Icon(Icons.calendar_month, size: 18,
                    color: _filterDate != null
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant),
                  label: Text(_filterDate != null
                      ? _dateFmt.format(_filterDate!)
                      : 'Sana bo\'yicha filtr'),
                  backgroundColor: _filterDate != null
                      ? theme.colorScheme.primaryContainer : null,
                  onPressed: _pickDate,
                ),
              ),
              if (_filterDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _filterDate = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ]),
          ),
        ),
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.extended(
          heroTag: 'add',
          onPressed: _openAddDialog,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Qo\'shish'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'excel',
          onPressed: _uploading ? null : _pickAndUpload,
          icon: _uploading
              ? const SizedBox(height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_uploading ? 'Yuklanmoqda...' : 'Excel yuklash'),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)))])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 140),
                    children: [
                      // Stats card
                      if (_all.isNotEmpty)
                        _StatsCard(
                          called: _calledCount,
                          pending: _pendingCount,
                          totalDebt: _totalDebt,
                          moneyFmt: _moneyFmt,
                        ),
                      // Empty state
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.inbox_outlined, size: 48,
                                color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              _all.isEmpty
                                  ? 'Hali raqam yo\'q.'
                                  : _filterDate != null
                                      ? '${_dateFmt.format(_filterDate!)} sanasida raqam yo\'q.'
                                      : 'Raqam topilmadi.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ]),
                        )
                      else
                        ...visible.map((n) => _NumberTile(
                          entry: n,
                          moneyFmt: _moneyFmt,
                          dateFmt: _dateFmt,
                          onHistory: n.callCount > 0
                              ? () => _showCallHistory(n) : null,
                        )),
                    ],
                  ),
      ),
    );
  }
}

// ─── Stats card ────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int called;
  final int pending;
  final double totalDebt;
  final NumberFormat moneyFmt;

  const _StatsCard({
    required this.called,
    required this.pending,
    required this.totalDebt,
    required this.moneyFmt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Statistika',
              style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 8, children: [
            _s(Icons.schedule, Colors.orange, 'Kutilmoqda', '$pending'),
            _s(Icons.check_circle, Colors.green, 'Qo\'ng\'iroq qilindi', '$called'),
            if (totalDebt > 0)
              _s(Icons.payments, Colors.deepOrange, 'Umumiy qarz',
                  moneyFmt.format(totalDebt)),
          ]),
        ]),
      ),
    );
  }

  Widget _s(IconData icon, Color color, String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 5),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ]);
  }
}

// ─── Number tile ────────────────────────────────────────────────────────────

class _NumberTile extends StatelessWidget {
  final PhoneNumberEntry entry;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final VoidCallback? onHistory;

  const _NumberTile({
    required this.entry,
    required this.moneyFmt,
    required this.dateFmt,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = entry;
    final called = n.callCount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: called
                ? Colors.green.withOpacity(0.15)
                : Colors.orange.withOpacity(0.15),
            child: Icon(
              called ? Icons.check_circle : Icons.schedule,
              color: called ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                n.fullName != null && n.fullName!.isNotEmpty
                    ? n.fullName! : n.number,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if (n.fullName != null && n.fullName!.isNotEmpty)
                Text(n.number,
                    style: TextStyle(
                        color: theme.colorScheme.outline, fontSize: 12)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (n.entryDate != null)
                  _chip(Icons.event, dateFmt.format(n.entryDate!),
                      theme.colorScheme.primary),
                if (n.contractNumber != null && n.contractNumber!.isNotEmpty)
                  _chip(Icons.description_outlined, n.contractNumber!,
                      Colors.indigo),
                if (n.debt > 0)
                  _chip(Icons.payments_outlined,
                      'Qarz: ${moneyFmt.format(n.debt)}', Colors.deepOrange),
                if (called)
                  GestureDetector(
                    onTap: onHistory,
                    child: _chip(
                      Icons.phone_forwarded,
                      '${n.callCount} marta${n.calledAt != null ? ' — ${DateFormat('dd.MM HH:mm').format(n.calledAt!)}' : ''}'
                      '${onHistory != null ? ' 🔍' : ''}',
                      Colors.green,
                    ),
                  )
                else
                  _chip(Icons.hourglass_empty, 'Hali qo\'ng\'iroq yo\'q',
                      Colors.grey),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
