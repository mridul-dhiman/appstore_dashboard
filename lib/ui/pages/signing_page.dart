import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../widgets.dart';

/// Certificates, identifiers, profiles and devices: the Developer-portal side of the same API key.
class SigningPage extends StatefulWidget {
  const SigningPage({super.key, required this.client});
  final AscClient client;

  @override
  State<SigningPage> createState() => _SigningPageState();
}

class _SigningPageState extends State<SigningPage> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          PageHeader(title: 'Signing', subtitle: 'Certificates, identifiers, profiles and devices', reload: _reload),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 16),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Certificates'),
                  Tab(text: 'Identifiers'),
                  Tab(text: 'Profiles'),
                  Tab(text: 'Devices'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _List(
                  controller: _reload,
                  // certificateContent is the whole certificate; leave it out.
                  load: () => c.all('/v1/certificates', {
                    'limit': '200',
                    'fields[certificates]': 'name,displayName,certificateType,expirationDate,serialNumber,platform',
                  }),
                  empty: 'No certificates.',
                  tile: (r, _) => ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(
                      '${prettyEnum(r.str('certificateType'))} · ${r.str('displayName') ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${r.str('name') ?? ''} · serial ${r.str('serialNumber') ?? ''}'),
                    trailing: _Expiry(r.date('expirationDate')),
                  ),
                ),
                _List(
                  controller: _reload,
                  load: () => c.all('/v1/bundleIds', {'limit': '200', 'sort': 'name'}),
                  empty: 'No identifiers.',
                  tile: (r, _) => ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: Text(r.str('identifier') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${r.str('name')} · ${prettyPlatform(r.str('platform'))} · team ${r.str('seedId')}'),
                  ),
                ),
                _List(
                  controller: _reload,
                  load: () => c.all('/v1/profiles', {
                    'limit': '200',
                    'fields[profiles]': 'name,profileType,profileState,expirationDate,createdDate',
                  }),
                  empty: 'No profiles.',
                  tile: (r, _) => ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${prettyEnum(r.str('profileType'))} · created ${fmtDate(r.date('createdDate'))}'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [StateChip(r.str('profileState')), _Expiry(r.date('expirationDate'))],
                    ),
                  ),
                ),
                _List(
                  controller: _reload,
                  load: () => c.all('/v1/devices', {'limit': '200', 'sort': 'name'}),
                  empty: 'No registered devices.',
                  tile: (r, _) => ListTile(
                    leading: Icon(r.str('deviceClass') == 'IPAD' ? Icons.tablet_mac : Icons.phone_iphone),
                    title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: SelectableText('${r.str('model') ?? prettyEnum(r.str('deviceClass'))} · ${r.str('udid')}'),
                    trailing: StateChip(r.str('status')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Expiry extends StatelessWidget {
  const _Expiry(this.date);
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    if (date == null) return const SizedBox.shrink();
    final days = date!.difference(DateTime.now()).inDays;
    final color = days < 0
        ? const Color(0xFFD13438)
        : days < 30
        ? const Color(0xFFB77300)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      days < 0 ? 'Expired ${fmtDate(date)}' : 'Expires ${fmtDate(date)}',
      style: TextStyle(color: color, fontWeight: days < 30 ? FontWeight.w700 : null, fontSize: 13),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller, required this.load, required this.tile, required this.empty});
  final ReloadController controller;
  final Future<ResourcePage> Function() load;
  final Widget Function(Resource r, ResourcePage p) tile;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      controller: controller,
      load: load,
      builder: (context, p) {
        if (p.data.isEmpty) return EmptyView(empty);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            RowsCard(children: [for (final r in p.data) tile(r, p)]),
          ],
        );
      },
    );
  }
}
