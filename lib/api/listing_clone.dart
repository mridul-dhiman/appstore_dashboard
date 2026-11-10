import 'listing.dart';
import 'listing_draft.dart';
import 'models.dart';

/// The fields that can be copied from one locale to others: release notes and promotional text.
const cloneableFields = [
  ListingField('whatsNew', "What's new in this version", max: 4000),
  ListingField('promotionalText', 'Promotional text', max: 170),
];

/// One text to stage on another locale.
class CloneEdit {
  CloneEdit({required this.locId, required this.locale, required this.field, required this.before, required this.after});
  final String locId;
  final String locale;
  final ListingField field;
  final String before; // what Apple has now
  final String after; // the source locale's text
}

/// What copying [fields] from the source text onto [targets] would change. [sourceText] gives the text to copy (staged
/// edits included); nothing is planned for a field that is empty in the source, is not editable on this version, or
/// already reads the same on the target.
List<CloneEdit> planClone({
  required String Function(String fieldKey) sourceText,
  required List<Resource> targets,
  required Iterable<ListingField> fields,
  required bool versionEditable,
}) {
  final out = <CloneEdit>[];
  for (final f in fields) {
    if (!isFieldEditable(f.key, versionEditable: versionEditable)) continue;
    final text = sourceText(f.key).trim();
    if (text.isEmpty) continue;
    for (final t in targets) {
      final before = t.str(f.key) ?? '';
      if (before == text) continue;
      out.add(CloneEdit(locId: t.id, locale: t.str('locale') ?? t.id, field: f, before: before, after: text));
    }
  }
  return out;
}

/// Stages every edit in [draft]; returns how many.
int stageClone(ListingDraft draft, List<CloneEdit> edits) {
  for (final e in edits) {
    draft.setText(target: 'version', locId: e.locId, locale: e.locale, field: e.field, before: e.before, after: e.after);
  }
  return edits.length;
}
