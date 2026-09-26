import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user.dart';
import '../../models/phone_number.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/call_service.dart';
import '../../services/socket_service.dart';
import '../login_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  final AppUser user;
  final String token;
  const WorkerHomeScreen({super.key, required this.user, required this.token});

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  late final ApiService _api = ApiService(widget.token);
  final _socket = SocketService();
  final _callService = CallService();
  final _dateFmt = DateFormat('dd.MM.yyyy');
  final _moneyFmt = NumberFormat.decimalPattern('uz');

  List<PhoneNumberEntry> _allNumbers = [];
  bool _loading = true;
  String? _error;
  int? _callingId;
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _load();
    _socket.connectAsWorker(widget.user.id);
    _socket.onNumbersUploaded((_) => _load());
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<PhoneNumberEntry> get _visible {
    Iterable<PhoneNumberEntry> r = _allNumbers.where((n) => !n.isResolved);
    if (_filterDate != null) {
      r = r.where((n) => n.entryDate != null && _isSameDay(n.entryDate!, _filterDate!));
    }
    return r.toList();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      setState(() => _allNumbers = await _api.fetchMyNumbers());
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
      helpText: 'Sana tanlang', cancelText: 'Bekor', confirmText: 'OK',
    );
    if (p != null) setState(() => _filterDate = p);
  }

  Future<void> _call(PhoneNumberEntry entry) async {
    if (_callingId != null) return;
    setState(() => _callingId = entry.id);
    try {
      await _callService.callAndTrack(
        number: entry.number,
        onAnswered: () async {
          try {
            final updated = await _api.markCalled(entry.id);
            if (!mounted) return;
            setState(() {
              entry.status = updated.status;
              entry.calledAt = updated.calledAt;
              entry.callCount = updated.callCount;
              _allNumbers.sort((a, b) => a.isCalled == b.isCalled ? 0 : (a.isCalled ? 1 : -1));
            });
          } catch (_) {}
        },
        onEnded: () { if (mounted) setState(() => _callingId = null); },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _callingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _changeDate(PhoneNumberEntry entry) async {
    final p = await showDatePicker(
      context: context,
      initialDate: entry.entryDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      helpText: 'Yangi sana', cancelText: 'Bekor', confirmText: 'Saqlash',
    );
    if (p == null) return;
    try {
      final updated = await _api.changeEntryDate(entry.id, p);
      if (!mounted) return;
      setState(() => entry.entryDate = updated.entryDate);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    _socket.dispose(); _callService.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  @override
  void dispose() { _socket.dispose(); _callService.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final pending = visible.where((n) => !n.isCalled).length;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Mening raqamlarim'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
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
                      ? _dateFmt.format(_filterDate!) : 'Sana bo\'yicha filtr'),
                  backgroundColor: _filterDate != null
                      ? theme.colorScheme.primaryContainer : null,
                  onPressed: _pickDate,
                ),
              ),
              if (_filterDate != null) ...[
                const SizedBox(width: 8),
                IconButton(onPressed: () => setState(() => _filterDate = null),
                    icon: const Icon(Icons.close)),
              ],
            ]),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)))])
                : visible.isEmpty
                    ? ListView(children: [
                        Padding(padding: const EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              _filterDate != null
                                  ? '${_dateFmt.format(_filterDate!)} sanasida raqam yo\'q.'
                                  : 'Hozircha sizga raqam yuklanmagan.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ]),
                        ),
                      ])
                    : Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Kutilmoqda: $pending ta',
                                style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700)),
                              Text('Jami: ${visible.length} ta',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.outline)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final n = visible[i];
                              return _WorkerCard(
                                key: ValueKey(n.id),
                                entry: n,
                                isCalling: _callingId == n.id,
                                dateFmt: _dateFmt,
                                moneyFmt: _moneyFmt,
                                onCall: () => _call(n),
                                onChangeDate: () => _changeDate(n),
                              );
                            },
                          ),
                        ),
                      ]),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  final PhoneNumberEntry entry;
  final bool isCalling;
  final DateFormat dateFmt;
  final NumberFormat moneyFmt;
  final VoidCallback onCall;
  final VoidCallback onChangeDate;

  const _WorkerCard({
    super.key,
    required this.entry,
    required this.isCalling,
    required this.dateFmt,
    required this.moneyFmt,
    required this.onCall,
    required this.onChangeDate,
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
      child: InkWell(
        onTap: isCalling ? null : onCall,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  called ? Colors.green.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
              child: isCalling
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(called ? Icons.check_circle : Icons.call,
                      color: called ? Colors.green : Colors.blue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  n.fullName != null && n.fullName!.isNotEmpty
                      ? n.fullName! : n.number,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (n.fullName != null && n.fullName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(n.number,
                        style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
                  ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  // Tappable date chip
                  GestureDetector(
                    onTap: onChangeDate,
                    child: _chip(
                      context,
                      icon: Icons.event,
                      label: n.entryDate != null
                          ? dateFmt.format(n.entryDate!) : 'Sana yo\'q',
                      color: theme.colorScheme.primary,
                      trailing: const Icon(Icons.edit, size: 10),
                    ),
                  ),
                  if (n.contractNumber != null && n.contractNumber!.isNotEmpty)
                    _chip(context,
                        icon: Icons.description_outlined,
                        label: n.contractNumber!,
                        color: Colors.indigo),
                  if (n.debt > 0)
                    _chip(context,
                        icon: Icons.payments_outlined,
                        label: 'Qarz: ${moneyFmt.format(n.debt)}',
                        color: Colors.deepOrange),
                  if (called)
                    _chip(context,
                        icon: Icons.phone_forwarded,
                        label: '${n.callCount} marta qo\'ng\'iroq'
                            '${n.calledAt != null ? ' — ${DateFormat('HH:mm').format(n.calledAt!)}' : ''}',
                        color: Colors.green)
                  else
                    _chip(context,
                        icon: Icons.touch_app,
                        label: 'Bosib qo\'ng\'iroq qiling',
                        color: Colors.grey),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    Widget? trailing,
  }) {
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
            style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        if (trailing != null) ...[const SizedBox(width: 3), trailing],
      ]),
    );
  }
}
