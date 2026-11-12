import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/pricing.dart';
import '../widgets.dart';

class _PricingData {
  _PricingData(this.price, this.availability);
  final AppPriceInfo price;
  final TerritoryAvailability availability;
}

class PricingTab extends StatefulWidget {
  const PricingTab({super.key, required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<PricingTab> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<_PricingData> _load() async {
    final r = await Future.wait<Object>([
      loadAppPriceSchedule(widget.client, widget.appId),
      loadAppAvailability(widget.client, widget.appId),
    ]);
    return _PricingData(r[0] as AppPriceInfo, r[1] as TerritoryAvailability);
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<_PricingData>(
      controller: _reload,
      load: _load,
      builder: (context, d) => _Body(client: widget.client, appId: widget.appId, data: d, onReload: _reload.reload),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.client, required this.appId, required this.data, required this.onReload});
  final AscClient client;
  final String appId;
  final _PricingData data;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final price = data.price;
    final avail = data.availability;
    final baseName = price.baseTerritory?.id ?? '—';

    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 600 ? 3 : 1;
            final w = (c.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(width: w, child: Stat(label: 'Base territory', value: baseName, icon: Icons.public)),
                SizedBox(
                  width: w,
                  child: Stat(
                    label: 'Manual prices',
                    value: '${price.manualPrices.length}',
                    icon: Icons.attach_money,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: Stat(
                    label: 'Territories',
                    value: '${avail.territories.length}',
                    icon: Icons.language,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        const SectionLabel('Price schedule'),
        if (price.manualPrices.isEmpty && price.automaticPrices.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('No price set. The app is free or has no price schedule.')))
        else
          RowsCard(
            children: [
              for (final p in price.manualPrices)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text('Manual price · ${p.str('startDate') ?? 'no start date'}'),
                  subtitle: Text('Tier ${p.relId('appPriceTier') ?? '—'}'),
                  trailing: const StateChip('MANUAL', label: 'Manual'),
                ),
              for (final p in price.automaticPrices)
                ListTile(
                  leading: const Icon(Icons.auto_fix_high),
                  title: Text('Automatic price · ${p.str('startDate') ?? 'no start date'}'),
                  subtitle: Text('Tier ${p.relId('appPriceTier') ?? '—'}'),
                  trailing: const StateChip('ACTIVE', label: 'Automatic'),
                ),
            ],
          ),

        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: SectionLabel('Territory availability')),
            if (avail.availableInNewTerritories)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tooltip(
                  message: 'When Apple adds a new territory, the app becomes available there automatically.',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF1F8F45)),
                      const SizedBox(width: 4),
                      Text('Auto-available in new territories', style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (avail.territories.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('No territory availability data found.')))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final t in avail.territories)
                    Chip(
                      label: Text(t.str('territory') ?? t.id, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
