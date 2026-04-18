import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/core/widgets/loading_empty_error.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/server_profile.dart';
import '../data/server_profile_repository_impl.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serverProfilesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            tooltip: 'Audit trail',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => context.push('/audit'),
          ),
          IconButton(
            tooltip: 'Templates',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => context.push('/templates'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/servers/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search servers…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: serversAsync.when(
              loading: () => StatusViews.loading(),
              error: (e, _) => StatusViews.error(error: e),
              data: (servers) {
                final filtered = _filter(servers);
                if (servers.isEmpty) {
                  return StatusViews.empty(
                    icon: Icons.dns_outlined,
                    title: 'No servers yet',
                    description: 'Add your first VPS to get instant recovery controls on your phone.',
                    action: ElevatedButton.icon(
                      onPressed: () => context.push('/servers/add'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add server'),
                    ),
                  );
                }
                if (filtered.isEmpty) {
                  return StatusViews.empty(
                    icon: Icons.search_off,
                    title: 'No matches',
                    description: 'Nothing matched "$_query".',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ServerTile(server: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ServerProfile> _filter(List<ServerProfile> list) {
    if (_query.isEmpty) return list;
    return list.where((s) {
      return s.nickname.toLowerCase().contains(_query) ||
          s.hostnameOrIp.toLowerCase().contains(_query) ||
          s.tags.any((t) => t.toLowerCase().contains(_query));
    }).toList();
  }
}

class _ServerTile extends ConsumerWidget {
  final ServerProfile server;
  const _ServerTile({required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = StringBuffer()
      ..write('${server.username}@${server.hostnameOrIp}:${server.port}');
    if (server.lastConnectedAt != null) {
      subtitle.write('  ·  last ${DateFormat('MMM d HH:mm').format(server.lastConnectedAt!)}');
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/servers/${server.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.dns, color: AppTheme.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.nickname,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (server.isFavorite) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star, size: 16, color: AppTheme.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.toString(),
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: server.isFavorite ? 'Unfavorite' : 'Favorite',
                icon: Icon(
                  server.isFavorite ? Icons.star : Icons.star_border,
                  color: server.isFavorite ? AppTheme.warning : AppTheme.muted,
                ),
                onPressed: () => ref.read(serverProfileRepositoryProvider).toggleFavorite(server.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
