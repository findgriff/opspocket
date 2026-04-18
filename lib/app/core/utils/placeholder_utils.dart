/// Utilities for extracting and substituting {{placeholder}} tokens in command
/// templates.
///
/// Supported syntax: double-curly tokens like `{{service_name}}` or
/// `{{line_count}}`. Whitespace inside the braces is tolerated:
/// `{{ service_name }}` also works.
class PlaceholderUtils {
  PlaceholderUtils._();

  static final RegExp _pattern = RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}');

  /// Returns the ordered list of unique placeholder names in [template].
  static List<String> extract(String template) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in _pattern.allMatches(template)) {
      final name = m.group(1)!;
      if (seen.add(name)) out.add(name);
    }
    return out;
  }

  /// Substitutes [values] into [template]. Any missing placeholders are left
  /// as-is so callers can detect and surface them.
  static String substitute(String template, Map<String, String> values) {
    return template.replaceAllMapped(_pattern, (m) {
      final name = m.group(1)!;
      final v = values[name];
      return v ?? m.group(0)!;
    });
  }

  /// Returns placeholder names that are present in [template] but missing
  /// from [values].
  static List<String> missing(String template, Map<String, String> values) {
    return extract(template).where((k) => !values.containsKey(k) || values[k]!.isEmpty).toList();
  }

  /// True if the template contains at least one unresolved placeholder after
  /// substitution.
  static bool hasUnresolved(String rendered) => _pattern.hasMatch(rendered);
}
