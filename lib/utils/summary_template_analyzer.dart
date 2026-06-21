class SummaryTemplateAnalysis {
  const SummaryTemplateAnalysis({
    required this.styleName,
    required this.sections,
    required this.numberingStyle,
    required this.actionSection,
    required this.preview,
  });

  final String styleName;
  final List<String> sections;
  final String numberingStyle;
  final String actionSection;
  final String preview;

  String toStorageText() {
    final buffer = StringBuffer()
      ..writeln('样式：$styleName')
      ..writeln('编号：$numberingStyle')
      ..writeln('待办：$actionSection')
      ..write('栏目：');
    buffer.write(sections.isEmpty ? '未识别' : sections.join(' / '));
    return buffer.toString();
  }
}

class SummaryTemplateAnalyzer {
  const SummaryTemplateAnalyzer._();

  static SummaryTemplateAnalysis analyze(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final sections = _detectSections(lines);
    final numberingStyle = _detectNumbering(lines);
    final actionSection = _detectActionSection(lines);
    final styleName = _detectStyle(sections, numberingStyle, lines);
    final preview = lines.take(8).join('\n');
    return SummaryTemplateAnalysis(
      styleName: styleName,
      sections: sections,
      numberingStyle: numberingStyle,
      actionSection: actionSection,
      preview: preview,
    );
  }

  static List<String> _detectSections(List<String> lines) {
    final sections = <String>[];
    final headingPattern = RegExp(
      r'^(会议时间|参会人员|会议摘要|会议概要|会议纪要|主要内容|结论|待办事项|行动项|风险|备注|议题|决定事项)[:：]?$',
    );
    for (final line in lines) {
      final normalized =
          line.replaceAll(RegExp(r'^[#\s一二三四五六七八九十、.0-9-]+'), '');
      if (headingPattern.hasMatch(normalized)) {
        sections.add(normalized.replaceAll(RegExp(r'[:：]$'), ''));
        continue;
      }
      if (line.endsWith('：') || line.endsWith(':')) {
        final label = line.substring(0, line.length - 1).trim();
        if (label.length <= 12) sections.add(label);
      }
    }
    return sections.toSet().toList();
  }

  static String _detectNumbering(List<String> lines) {
    final numeric =
        lines.where((line) => RegExp(r'^\d+[.、]').hasMatch(line)).length;
    final chinese = lines
        .where((line) => RegExp(r'^[一二三四五六七八九十]+[、.]').hasMatch(line))
        .length;
    final bullet =
        lines.where((line) => RegExp(r'^[-*•]').hasMatch(line)).length;
    if (numeric >= chinese && numeric >= bullet && numeric > 0) {
      return '阿拉伯数字编号';
    }
    if (chinese >= numeric && chinese >= bullet && chinese > 0) {
      return '中文序号';
    }
    if (bullet > 0) {
      return '项目符号';
    }
    return '段落式';
  }

  static String _detectActionSection(List<String> lines) {
    final text = lines.join('\n');
    if (RegExp(r'(待办事项|行动项|负责人|责任人|截止|完成时间)').hasMatch(text)) {
      return '包含待办/责任人字段';
    }
    return '未发现独立待办字段';
  }

  static String _detectStyle(
    List<String> sections,
    String numberingStyle,
    List<String> lines,
  ) {
    if (sections.length >= 3 && numberingStyle != '段落式') {
      return '分栏编号式会议纪要';
    }
    if (sections.length >= 3) return '分栏段落式会议纪要';
    if (numberingStyle != '段落式') return '编号条目式纪要';
    if (lines.length <= 4) return '简短摘要式纪要';
    return '自由段落式纪要';
  }
}
