import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/command_template.dart';
import '../data/command_template_repository_impl.dart';
import 'placeholder_prompt.dart';

/// Bottom-sheet palette: searchable, grouped by category, shows favorites
/// and recents. Returns the rendered command on selection (or null).
class SlashPalette {
  SlashPalette._();

  static Future<String?> show({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => _PaletteBody(scroll: controller),
      ),
    );
  }
}

class _PaletteBody extends ConsumerStatefulWidget {
  final ScrollController scroll;
  const _PaletteBody({required this.scroll});

  @override
  ConsumerState<_PaletteBody> createState() => _PaletteBodyState();
}

class _PaletteBodyState extends ConsumerState<_PaletteBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commandTemplatesStreamProvider);
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
      data: (templates) {
        final filtered = _filter(templates);
        final grouped = _group(filtered);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.muted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search commands or type / for slash…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: widget.scroll,
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Text(
                            _categoryLabel(entry.key),
                            style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        for (final t in entry.value) _PaletteRow(template: t),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _categoryLabel(CommandCategory c) {
    switch (c) {
      case CommandCategory.status:
        return 'Status';
      case CommandCategory.logs:
        return 'Logs';
      case CommandCategory.restart:
        return 'Restart';
      case CommandCategory.reboot:
        return 'Reboot';
      case CommandCategory.docker:
        return 'Docker';
      case CommandCategory.pm2:
        return 'PM2';
      case CommandCategory.systemd:
        return 'Systemd';
      case CommandCategory.tmux:
        return 'tmux';
      case CommandCategory.generic:
        return 'Generic';
      case CommandCategory.custom:
        return 'Custom';
      case CommandCategory.openclaw:
        return 'OpenClaw';
    }
  }

  List<CommandTemplate> _filter(List<CommandTemplate> all) {
    if (_query.isEmpty) return all;
    final q = _query.startsWith('/') ? _query.substring(1) : _query;
    return all.where((t) {
      return t.name.toLowerCase().contains(q) ||
          t.slash.toLowerCase().contains(q) ||
          t.commandText.toLowerCase().contains(q) ||
          (t.description ?? '').toLowerCase().contains(q) ||
          t.applicableStack.any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  Map<CommandCategory, List<CommandTemplate>> _group(List<CommandTemplate> list) {
    final out = <CommandCategory, List<CommandTemplate>>{};
    // Favorites first virtual group
    final favs = list.where((t) => t.isFavorite).toList();
    final rest = list.where((t) => !t.isFavorite).toList();
    if (favs.isNotEmpty) {
      out[CommandCategory.custom] = favs; // reuse enum; we re-label below
    }
    for (final t in rest) {
      out.putIfAbsent(t.category, () => []).add(t);
    }
    return out;
  }
}

class _PaletteRow extends ConsumerWidget {
  final CommandTemplate template;
  const _PaletteRow({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        template.dangerous ? Icons.warning_amber_rounded : Icons.terminal,
        color: template.dangerous ? Colors.orange : AppTheme.accent,
      ),
      title: Row(
        children: [
          Text(template.slash, style: AppTheme.mono(size: 13, color: AppTheme.accent)),
          const SizedBox(width: 10),
          Flexible(child: Text(template.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(
        template.commandText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.mono(size: 12, color: AppTheme.muted),
      ),
      trailing: IconButton(
        icon: Icon(
          template.isFavorite ? Icons.star : Icons.star_border,
          color: template.isFavorite ? AppTheme.warning : AppTheme.muted,
          size: 20,
        ),
        onPressed: () => ref.read(commandTemplateRepositoryProvider).toggleFavorite(template.id),
      ),
      onTap: () async {
        final rendered = await PlaceholderPromptSheet.show(context: context, template: template);
        if (rendered != null && context.mounted) {
          Navigator.of(context).pop(rendered);
        }
      },
    );
  }
}
