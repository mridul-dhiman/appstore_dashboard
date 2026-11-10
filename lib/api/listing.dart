/// Which store-listing fields can be changed in which state. Apple is the final judge (it rejects what is not allowed),
/// this only decides what the form lets you type into.
const editableVersionStates = {
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
  'REJECTED',
  'METADATA_REJECTED',
  'WAITING_FOR_REVIEW',
  'INVALID_BINARY',
};

bool isVersionEditable(String? state) => editableVersionStates.contains(state);

/// Promotional text is the one field that can be changed on a version that is already live.
bool isFieldEditable(String field, {required bool versionEditable}) => versionEditable || field == 'promotionalText';

class ListingField {
  const ListingField(this.key, this.label, {this.max, this.lines = 1, this.helper});
  final String key;
  final String label;
  final int? max;
  final int lines;
  final String? helper;
}

const versionFields = [
  ListingField('promotionalText', 'Promotional text', max: 170, lines: 3, helper: 'Can be changed any time, without a new version.'),
  ListingField('description', 'Description', max: 4000, lines: 10),
  ListingField('keywords', 'Keywords', max: 100, lines: 2, helper: 'Comma-separated, no spaces after commas.'),
  ListingField('whatsNew', "What's new in this version", max: 4000, lines: 5),
  ListingField('supportUrl', 'Support URL'),
  ListingField('marketingUrl', 'Marketing URL'),
];

const infoFields = [
  ListingField('name', 'App name', max: 30),
  ListingField('subtitle', 'Subtitle', max: 30),
  ListingField('privacyPolicyUrl', 'Privacy policy URL'),
];

/// Only the fields whose text differs from what was loaded. Null on the server and '' in the form count as the same.
Map<String, String> changedFields(Map<String, String?> original, Map<String, String> current) {
  final out = <String, String>{};
  for (final e in current.entries) {
    if ((original[e.key] ?? '') != e.value) out[e.key] = e.value;
  }
  return out;
}

/// Fields over their length limit, as readable problems.
List<String> lengthProblems(Iterable<ListingField> fields, Map<String, String> values) => [
      for (final f in fields)
        if (f.max != null && (values[f.key]?.length ?? 0) > f.max!) '${f.label} is over ${f.max} characters (${values[f.key]!.length}).',
    ];

Map<String, dynamic> localizationPatchBody(String type, String id, Map<String, String> attributes) => {
      'data': {'type': type, 'id': id, 'attributes': attributes},
    };

/// Fill Apple's `{w}x{h}bb.{f}` image template for a thumbnail [width] pixels wide.
String? thumbnailUrl(String? template, int? w, int? h, {int width = 320}) {
  if (template == null || w == null || h == null || w == 0) return null;
  final height = (width * h / w).round();
  return template.replaceAll('{w}', '$width').replaceAll('{h}', '$height').replaceAll('{f}', 'png');
}
