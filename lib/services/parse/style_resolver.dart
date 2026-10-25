import '../../models/ass_style.dart';
import '../../models/merge_options.dart';

class ResolvedStyles {
  const ResolvedStyles({
    required this.lines,
    required this.baseResY,
    required this.names,
    required this.hdr,
  });

  final List<String> lines;
  final int baseResY;
  final StyleNames names;
  final bool hdr;
}

class StyleResolver {
  static ResolvedStyles resolve(MergeOptions options) {
    final hdr = options.hdrSubtitle;
    final effective = StyleCatalog.effectiveStyles(
      styleLines: options.styleLines,
      baseResY: options.styleBaseResY,
      mode: options.processMode,
    );
    var lines = StyleCatalog.linesFor(effective.lines, hdr: hdr);
    var baseResY = effective.baseResY;
    if (lines.isEmpty) {
      lines = StyleCatalog.linesFor(StyleCatalog.defaultStyleLines, hdr: hdr);
      baseResY = StyleCatalog.defaultBaseResY;
    }
    if (baseResY <= 0) baseResY = StyleCatalog.defaultBaseResY;
    return ResolvedStyles(
      lines: lines,
      baseResY: baseResY,
      names: StyleCatalog.namesFor(lines, hdr: hdr),
      hdr: hdr,
    );
  }
}
