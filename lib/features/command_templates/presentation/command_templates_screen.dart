import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/widgets/loading_empty_error.dart';
import '../../../app/theme/app_theme.dart';
import '../data/command_template_repository_impl.dart';

class CommandTemplatesScreen extends ConsumerWidget {
  const CommandTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commandTemplatesStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Command templates')),
      body: async.when(
        loading: () => StatusViews.loading(),
        error: (e, _) => StatusViews.error(error: e),
        data: (list) {
          if (list.isEmpty) {
            return StatusViews.empty(
              title: 'No templates',
              description: 'Built-ins load automatically on first run.',
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = list[i];
              return ListTile(
                title: Row(
                  children: [
                    Text(t.slash, style: AppTheme.mono(size: 13, color: AppTheme.accent)),
                    const SizedBox(width: 10),
                    Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
                    if (t.dangerous) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 16),
                    ],
                  ],
                ),
                subtitle: Text(
                  t.commandText,
                  style: AppTheme.mono(size: 12, color: AppTheme.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: Icon(
                    t.isFavorite ? Icons.star : Icons.star_border,
                    color: t.isFavorite ? AppTheme.warning : AppTheme.muted,
                  ),
                  onPressed: () => ref.read(commandTemplateRepositoryProvider).toggleFavorite(t.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
