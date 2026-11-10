import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../widgets.dart';

/// Builds with their pre-release version and app name resolved.
class _Tf {
  _Tf(this.builds, this.total, this._versions, this._appByBuild, this._apps);
  final List<Resource> builds;
  final int? total;
  final ResourcePage _versions;
  final Map<String, String?> _appByBuild;
  final ResourcePage _apps;

  String appName(Resource b) => _apps.inc('apps', _appByBuild[b.id])?.str('name') ?? 'App';
  String version(Resource b) => _versions.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '';
}

class TestFlightPage extends StatefulWidget {
  const TestFlightPage({super.key, required this.client});
  final AscClient client;

  @override
  State<TestFlightPage> createState() => _TestFlightPageState();
}

class _TestFlightPageState extends State<TestFlightPage> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PageHeader(title: 'TestFlight', subtitle: 'Latest builds across all apps', reload: _reload),
      Expanded(
        child: LoadView<_Tf>(
          controller: _reload,
          load: () async {
            // Asking for both includes in one request is ~4x slower than two parallel requests, so merge by build id.
            const base = {'sort': '-uploadedDate', 'limit': '100'};
            final r = await Future.wait([
              widget.client.page('/v1/builds', {...base, 'include': 'preReleaseVersion'}),
              widget.client.page('/v1/builds', {...base, 'include': 'app', 'fields[builds]': 'app', 'fields[apps]': 'name'}),
            ]);
            return _Tf(r[0].data, r[0].total, r[0], {for (final b in r[1].data) b.id: b.relId('app')}, r[1]);
          },
          builder: (context, tf) {
            final p = tf;
            if (p.builds.isEmpty) return const EmptyView('No builds uploaded yet.');
            final processing = p.builds.where((b) => b.str('processingState') == 'PROCESSING').length;
            final expiring = p.builds.where((b) {
              final e = b.date('expirationDate');
              return b.flag('expired') != true && e != null && e.difference(DateTime.now()).inDays < 14;
            }).length;
            return ListView(padding: const EdgeInsets.fromLTRB(40, 0, 40, 40), children: [
              Row(children: [
                Expanded(child: Stat(label: 'Builds shown', value: '${p.builds.length}${p.total != null ? ' of ${p.total}' : ''}', icon: Icons.inventory_2_outlined)),
                const SizedBox(width: 12),
                Expanded(child: Stat(label: 'Processing', value: '$processing', icon: Icons.sync, tone: const Color(0xFFB77300))),
                const SizedBox(width: 12),
                Expanded(child: Stat(label: 'Expiring in 14 days', value: '$expiring', icon: Icons.timer_outlined, tone: const Color(0xFFD13438))),
              ]),
              const SizedBox(height: 16),
              RowsCard(children: [
                for (final b in p.builds)
                  ListTile(
                    leading: const Icon(Icons.flight_takeoff),
                    title: Text(
                      '${p.appName(b)}  ${p.version(b)} (${b.str('version')})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('Uploaded ${fmtDateTime(b.date('uploadedDate'))} · ${b.flag('expired') == true ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'}'),
                    trailing: StateChip(b.flag('expired') == true ? 'EXPIRED' : b.str('processingState')),
                  ),
              ]),
            ]);
          },
        ),
      ),
    ]);
  }
}
