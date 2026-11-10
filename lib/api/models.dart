/// A JSON:API resource object as returned by the App Store Connect API.
class Resource {
  Resource({required this.id, required this.type, required this.attributes, required this.relationships});

  final String id;
  final String type;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic> relationships;

  factory Resource.fromJson(Map<String, dynamic> j) => Resource(
        id: j['id'].toString(),
        type: j['type'].toString(),
        attributes: (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
        relationships: (j['relationships'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  String? str(String key) {
    return attributes[key]?.toString();
  }

  int? integer(String key) {
    final v = attributes[key];
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  bool? flag(String key) {
    final v = attributes[key];
    return v is bool ? v : null;
  }

  DateTime? date(String key) {
    final s = str(key);
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  List<String> list(String key) {
    final v = attributes[key];
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  }

  /// Id of a to-one relationship, when the API included its linkage.
  String? relId(String name) {
    final data = (relationships[name] as Map?)?['data'];
    return data is Map ? data['id']?.toString() : null;
  }

  /// Ids of a to-many relationship, when the API included its linkage.
  List<String> relIds(String name) {
    final data = (relationships[name] as Map?)?['data'];
    return data is List ? data.map((e) => (e as Map)['id'].toString()).toList() : const [];
  }
}

/// One or more merged pages of a collection, plus everything the API `include`d.
class ResourcePage {
  ResourcePage({required this.data, Map<String, Resource>? included, this.next, this.total})
      : included = included ?? {};

  final List<Resource> data;
  final Map<String, Resource> included;
  final String? next;
  final int? total;

  Resource? inc(String type, String? id) => id == null ? null : included['$type/$id'];

  static ResourcePage fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final list = data is List
        ? data.map((e) => Resource.fromJson((e as Map).cast<String, dynamic>())).toList()
        : data is Map
            ? [Resource.fromJson(data.cast<String, dynamic>())]
            : <Resource>[];
    final included = <String, Resource>{};
    for (final e in (json['included'] as List? ?? const [])) {
      final r = Resource.fromJson((e as Map).cast<String, dynamic>());
      included['${r.type}/${r.id}'] = r;
    }
    final links = json['links'] as Map?;
    final meta = json['meta'] as Map?;
    return ResourcePage(
      data: list,
      included: included,
      next: links?['next']?.toString(),
      total: (meta?['paging'] as Map?)?['total'] as int?,
    );
  }
}
