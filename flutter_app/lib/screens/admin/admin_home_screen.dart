import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user.dart';
import '../../models/phone_number.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../login_screen.dart';
import 'worker_detail_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final AppUser user;
  final String token;
  const AdminHomeScreen({super.key, required this.user, required this.token});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late final ApiService _api = ApiService(widget.token);
  final _socket = SocketService();
  final _moneyFmt = NumberFormat.decimalPattern('uz');

  List<WorkerSummary> _workers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _socket.connectAsAdmin();
    _socket.onNumberCalled((_) => _load());
    _socket.onPaymentCollected((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      setState(() => _workers = await _api.fetchWorkers());
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    _socket.dispose();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  Future<void> _openDebtUrlDialog() async {
    final urlCtrl = TextEditingController();
    bool loadingUrl = true;
    bool saving = false;

    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (loadingUrl) {
            _api.fetchDebtSourceUrl().then((url) {
              if (dialogCtx.mounted) setS(() { urlCtrl.text = url; loadingUrl = false; });
            }).catchError((_) {
              if (dialogCtx.mounted) setS(() => loadingUrl = false);
            });
          }

          Future<void> save() async {
            setS(() => saving = true);
            try {
              await _api.saveDebtSourceUrl(urlCtrl.text.trim());
              if (!dialogCtx.mounted) return;
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL saqlandi. Sinxronizatsiya boshlandi.')));
            } catch (e) {
              setS(() => saving = false);
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
            }
          }

          return AlertDialog(
            title: const Text('Qarz JSON manzili'),
            content: loadingUrl
                ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '{ "contracts": [\n'
                        '  { "contract_number": "SH-1024",\n'
                        '    "debt": 150000 },\n'
                        '  ...\n'
                        '] }',
                        style: TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      enabled: !saving,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        hintText: 'https://example.com/debts.json',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => save(),
                    ),
                  ]),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Yopish'),
              ),
              FilledButton(
                onPressed: (saving || loadingUrl) ? null : save,
                child: saving
                    ? const SizedBox(height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Saqlash'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() { _socket.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Ishchilar'),
        actions: [
          IconButton(
            tooltip: 'Qarz JSON manzili',
            onPressed: _openDebtUrlDialog,
            icon: const Icon(Icons.link),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)))])
                : _workers.isEmpty
                    ? ListView(children: [
                        Padding(padding: const EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.groups_outlined, size: 48, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              'Hozircha ishchilar yo\'q.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ]),
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                        itemCount: _workers.length,
                        itemBuilder: (_, i) {
                          final w = _workers[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            elevation: 0,
                            color: theme.colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: theme.colorScheme.outlineVariant),
                            ),
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => WorkerDetailScreen(
                                      token: widget.token, worker: w),
                                ));
                                _load();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          theme.colorScheme.primaryContainer,
                                      child: Text(
                                        w.name.isNotEmpty
                                            ? w.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: theme.colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(w.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15)),
                                          const SizedBox(height: 2),
                                          Text(w.phone,
                                              style: TextStyle(
                                                  color: theme.colorScheme.outline,
                                                  fontSize: 13)),
                                          const SizedBox(height: 6),
                                          Wrap(spacing: 6, runSpacing: 4, children: [
                                            _statChip('Kutilmoqda: ${w.pendingCount}',
                                                Colors.orange),
                                            _statChip('Qo\'ng\'iroq: ${w.calledCount}',
                                                Colors.green),
                                            if (w.totalDebt > 0)
                                              _statChip(
                                                'Qarz: ${_moneyFmt.format(w.totalDebt)}',
                                                Colors.deepOrange),
                                          ]),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
