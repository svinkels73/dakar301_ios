class Stage {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  Stage({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
  });

  factory Stage.fromJson(Map<String, dynamic> json) {
    return Stage(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate.toIso8601String().split('T')[0],
      'endDate': endDate.toIso8601String().split('T')[0],
    };
  }

  bool containsDate(DateTime date) {
    final checkDate = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !checkDate.isBefore(start) && !checkDate.isAfter(end);
  }

  @override
  String toString() => 'Stage($id: $name)';
}

class StagesConfig {
  final String rallyName;
  final List<Stage> stages;

  StagesConfig({
    required this.rallyName,
    required this.stages,
  });

  factory StagesConfig.fromJson(Map<String, dynamic> json) {
    return StagesConfig(
      rallyName: json['rallyName'] as String? ?? 'Dakar 2026',
      stages: (json['stages'] as List<dynamic>?)
          ?.map((s) => Stage.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rallyName': rallyName,
      'stages': stages.map((s) => s.toJson()).toList(),
    };
  }

  Stage? getStageForDate(DateTime date) {
    for (final stage in stages) {
      if (stage.containsDate(date)) {
        return stage;
      }
    }
    return null;
  }

  Stage? getCurrentStage() {
    return getStageForDate(DateTime.now());
  }
}

// Media categories
enum MediaCategory {
  videoGeneral('video_general', 'Video General'),
  videoEnglish('video_english', 'Video English'),
  videoArabic('video_arabic', 'Video Arabic'),
  photos('photos', 'Photo');

  final String id;
  final String displayName;

  const MediaCategory(this.id, this.displayName);

  bool get isPhoto => this == MediaCategory.photos;
  bool get isVideo => !isPhoto;
}
