import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../widgets.dart';
import 'app_detail_page.dart';

class AppSummary {
  AppSummary(this.app, this.version, this.build);
  final Resource app;
  final Resource? version;
  final Resource? build;

  String? get state => version?.str('appStoreState') ?? version?.str('appVersionState');
  bool get isLive => state == 'READY_FOR_SALE';

  /// Icon URL from the newest build's icon token (`{w}x{h}bb.{f}` is a template).
  String? iconUrl(int px) {
    final t = (build?.attributes['iconAssetToken'] as Map?)?['templateUrl'] as String?;
    return t?.replaceAll('{w}', '$px').replaceAll('{h}', '$px').replaceAll('{f}', 'png');
  }
}

Future<List<AppSummary>> loadApps(AscClient c) async {
  final apps = await c.all('/v1/apps', {'limit': '200', 'sort': 'name'});
  return Future.wait(apps.data.map((a) async {
    // One failing lookup should not blank the whole list.
    final results = await Future.wait([
      c.page('/v1/apps/${a.id}/appStoreVersions', {'limit': '1'}).then<Resource?>((p) => p.data.isEmpty ? null : p.data.first).catchError((_) => null),
      c.page('/v1/builds', {'filter[app]': a.id, 'sort': '-uploadedDate', 'limit': '1'}).then<Resource?>((p) => p.data.isEmpty ? null : p.data.first).catchError((_) => null),
    ]);
    return AppSummary(a, results[0], results[1]);
  }));
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.url, this.size = 52});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(size * 0.225)),
      child: Icon(Icons.apps, color: cs.onSurfaceVariant, size: size * 0.5),
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.225),
      child: Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}

class AppsPage extends StatefulWidget {
  const AppsPage({super.key, required this.client});
  final AscClient client;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PageHeader(title: 'Apps', subtitle: 'Everything this key can see', reload: _reload),
      Expanded(
        child: LoadView<List<AppSummary>>(
          controller: _reload,
          load: () => loadApps(widget.client),
          builder: (context, apps) {
            if (apps.isEmpty) return const EmptyView('This key can not see any apps.');
            final live = apps.where((a) => a.isLive).length;
            return ListView(padding: const EdgeInsets.fromLTRB(40, 0, 40, 40), children: [
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 700 ? 3 : 1;
                final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: w, child: Stat(label: 'Apps', value: '${apps.length}', icon: Icons.apps)),
                  SizedBox(width: w, child: Stat(label: 'Live on the App Store', value: '$live', icon: Icons.check_circle_outline, tone: const Color(0xFF1F8F45))),
                  SizedBox(width: w, child: Stat(label: 'Not live', value: '${apps.length - live}', icon: Icons.pending_outlined, tone: const Color(0xFFB77300))),
                ]);
              }),
              const SizedBox(height: 16),
              RowsCard(children: [
                for (final a in apps)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppDetailPage(client: widget.client, summary: a))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        AppIcon(url: a.iconUrl(120)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.app.str('name') ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(a.app.str('bundleId') ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (a.version != null) Text('v${a.version!.str('versionString')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          StateChip(a.state),
                        ]),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
              ]),
            ]);
          },
        ),
      ),
    ]);
  }
}
