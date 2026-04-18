/// Command template. Supports {{placeholder}} substitution at run time.
enum CommandCategory {
  status,
  logs,
  restart,
  reboot,
  docker,
  pm2,
  systemd,
  tmux,
  generic,
  custom,
  openclaw,
}

class CommandTemplate {
  final String id;
  final String name;
  final CommandCategory category;

  /// Raw command text. May contain {{placeholder}} tokens.
  final String commandText;

  /// Ordered unique placeholder names this template needs.
  final List<String> placeholders;

  /// True if running this command could cause data loss, downtime, or reboot.
  final bool dangerous;

  /// True if this template was seeded by the app (cannot be deleted, only copied).
  final bool isBuiltin;

  final bool isFavorite;
  final String? description;

  /// Optional compatibility hints (e.g. "linux", "docker", "pm2").
  final List<String> applicableStack;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CommandTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.commandText,
    this.placeholders = const [],
    this.dangerous = false,
    this.isBuiltin = false,
    this.isFavorite = false,
    this.description,
    this.applicableStack = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Slash-command shorthand (e.g. "/restart-service").
  String get slash {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '/$slug';
  }

  CommandTemplate copyWith({
    String? name,
    CommandCategory? category,
    String? commandText,
    List<String>? placeholders,
    bool? dangerous,
    bool? isFavorite,
    String? description,
    List<String>? applicableStack,
    DateTime? updatedAt,
  }) {
    return CommandTemplate(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      commandText: commandText ?? this.commandText,
      placeholders: placeholders ?? this.placeholders,
      dangerous: dangerous ?? this.dangerous,
      isBuiltin: isBuiltin,
      isFavorite: isFavorite ?? this.isFavorite,
      description: description ?? this.description,
      applicableStack: applicableStack ?? this.applicableStack,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
