import 'package:appstore_dashboard/api/listing.dart';
import 'package:appstore_dashboard/api/listing_clone.dart';
import 'package:appstore_dashboard/api/listing_draft.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

Resource loc(String id, String locale, {String? news, String? promo}) => Resource(
  id: id,
  type: 'appStoreVersionLocalizations',
  relationships: const {},
  attributes: {'locale': locale, 'whatsNew': news, 'promotionalText': promo},
);

void main() {
  final fr = loc('L2', 'fr-FR', news: 'Anciennes notes');
  final de = loc('L3', 'de-DE');
  final same = loc('L4', 'es-ES', news: 'Bug fixes', promo: 'Promo');

  String source(String k) => {'whatsNew': 'Bug fixes', 'promotionalText': 'Promo'}[k] ?? '';

  test('copies the chosen fields to every target, skipping ones that already match', () {
    final plan = planClone(sourceText: source, targets: [fr, de, same], fields: cloneableFields, versionEditable: true);
    expect(plan.map((e) => '${e.locale}:${e.field.key}').toList(), [
      'fr-FR:whatsNew',
      'de-DE:whatsNew',
      'fr-FR:promotionalText',
      'de-DE:promotionalText',
    ]);
    expect(plan.first.before, 'Anciennes notes');
    expect(plan.first.after, 'Bug fixes');
  });

  test('on a live version only the promotional text is copied', () {
    final plan = planClone(sourceText: source, targets: [fr], fields: cloneableFields, versionEditable: false);
    expect(plan.map((e) => e.field.key), ['promotionalText']);
  });

  test('an empty source field is never copied over text that exists', () {
    final plan = planClone(
      sourceText: (k) => k == 'whatsNew' ? '   ' : 'Promo',
      targets: [fr],
      fields: cloneableFields,
      versionEditable: true,
    );
    expect(plan.map((e) => e.field.key), ['promotionalText']);
  });

  test('staging puts edits in the changelist and sends nothing', () {
    final draft = ListingDraft();
    final n = stageClone(draft, planClone(sourceText: source, targets: [fr, de], fields: [cloneableFields.first], versionEditable: true));
    expect(n, 2);
    expect(draft.count, 2);
    expect(draft.textOverride('version', 'L2', 'whatsNew'), 'Bug fixes');
    expect(draft.changes().map((c) => c.locale).toSet(), {'fr-FR', 'de-DE'});
    // Staging the same text again, or reverting to Apple's value, does not duplicate or leave a ghost change.
    stageClone(draft, planClone(sourceText: source, targets: [fr], fields: [cloneableFields.first], versionEditable: true));
    expect(draft.count, 2);
    draft.setText(
      target: 'version',
      locId: 'L2',
      locale: 'fr-FR',
      field: const ListingField('whatsNew', 'x'),
      before: 'Anciennes notes',
      after: 'Anciennes notes',
    );
    expect(draft.count, 1);
  });
}
