/// A QuickAction is a user-facing big-button that maps to a command template.
/// Built-in actions come pre-seeded; users can reorder, hide, or clone them.
class QuickAction {
  final String id;
  final String label;
  final String? emoji;
  final String templateId;
  final int sortOrder;
  final bool visible;
  final bool isBuiltin;

  const QuickAction({
    required this.id,
    required this.label,
    this.emoji,
    required this.templateId,
    required this.sortOrder,
    this.visible = true,
    this.isBuiltin = false,
  });

  QuickAction copyWith({
    String? label,
    String? emoji,
    String? templateId,
    int? sortOrder,
    bool? visible,
  }) {
    return QuickAction(
      id: id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      templateId: templateId ?? this.templateId,
      sortOrder: sortOrder ?? this.sortOrder,
      visible: visible ?? this.visible,
      isBuiltin: isBuiltin,
    );
  }
}
