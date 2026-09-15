class Area {
  const Area({required this.id, required this.name});
  factory Area.fromJson(Map<String, dynamic> json) =>
      Area(id: json['id'] as int, name: json['name'] as String);
  final int id;
  final String name;
}

class Section {
  const Section({required this.id, required this.areaId, required this.name});
  factory Section.fromJson(Map<String, dynamic> json) => Section(
    id: json['id'] as int,
    areaId: json['area_id'] as int,
    name: json['name'] as String,
  );
  final int id;
  final int areaId;
  final String name;
}

class Machinery {
  const Machinery({
    required this.id,
    required this.sectionId,
    required this.name,
    this.sourceCode,
  });
  factory Machinery.fromJson(Map<String, dynamic> json) => Machinery(
    id: json['id'] as int,
    sectionId: json['section_id'] as int,
    name: json['name'] as String,
    sourceCode: json['source_code'] as int?,
  );
  final int id;
  final int sectionId;
  final String name;
  final int? sourceCode;
}
