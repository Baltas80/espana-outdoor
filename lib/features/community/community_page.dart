import 'package:flutter/material.dart';

import '../../app/design_system/colors.dart';
import '../../app/design_system/radii.dart';
import '../../app/design_system/spacing.dart';
import '../../app/design_system/typography.dart';

enum _CommunityTab { following, explore }

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  _CommunityTab _tab = _CommunityTab.following;
  final _searchController = TextEditingController();
  final Set<String> _likedPosts = <String>{};
  final Set<String> _savedPosts = <String>{};

  static const _posts = <_DemoPost>[
    _DemoPost(
      id: 'preview-1',
      author: 'Perfil de ejemplo',
      handle: '@ejemplo',
      activity: 'Senderismo',
      age: 'Vista previa',
      text:
          'Comparte aquí una experiencia de montaña, consejos del recorrido y lo que conviene preparar antes de salir.',
      place: 'Ubicación opcional',
      routeName: 'Tarjeta de ruta compartida',
      routeMeta: 'Geometría real · distancia · desnivel · GPX',
      likes: 18,
      comments: 4,
      icon: Icons.terrain_outlined,
    ),
    _DemoPost(
      id: 'preview-2',
      author: 'Perfil de ejemplo',
      handle: '@outdoor',
      activity: 'Descubrimiento',
      age: 'Vista previa',
      text:
          'Los descubrimientos pueden incluir miradores, fuentes, refugios y observaciones útiles para otras personas.',
      place: 'Lugar generalizado',
      likes: 9,
      comments: 2,
      icon: Icons.landscape_outlined,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showComposer() async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EOColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          EOSpacing.lg,
          EOSpacing.xl,
          EOSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + EOSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nueva publicación', style: EOTextStyles.title),
            const SizedBox(height: EOSpacing.sm),
            const Text(
              'Escribe una experiencia outdoor. En esta versión de demostración '
              'no se envían ni almacenan publicaciones.',
              style: EOTextStyles.secondary,
            ),
            const SizedBox(height: EOSpacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 5,
              maxLength: 1200,
              decoration: const InputDecoration(
                hintText: '¿Qué has descubierto en tu última salida?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: EOSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Añadir fotografías · próximamente'),
            ),
            const SizedBox(height: EOSpacing.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Cerrar borrador de demostración'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Borrador descartado: el servicio de publicaciones aún no está conectado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visiblePosts = _posts.where((post) {
      if (query.isEmpty) return true;
      return '${post.author} ${post.activity} ${post.text} ${post.place}'
          .toLowerCase()
          .contains(query);
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: EOColors.night,
      appBar: AppBar(
        title: const Text('Comunidad'),
        actions: [
          IconButton(
            tooltip: 'Crear publicación',
            onPressed: _showComposer,
            icon: const Icon(Icons.add_box_outlined),
          ),
          const SizedBox(width: EOSpacing.sm),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                EOSpacing.lg,
                EOSpacing.sm,
                EOSpacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aventuras que merecen compartirse.',
                    style: EOTextStyles.hero.copyWith(fontSize: 27),
                  ),
                  const SizedBox(height: EOSpacing.sm),
                  const Text(
                    'Experiencias, rutas y descubrimientos de la comunidad outdoor.',
                    style: EOTextStyles.body.copyWith(
                      color: EOColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: EOSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(EOSpacing.md),
                    decoration: BoxDecoration(
                      color: EOColors.orange.withValues(alpha: .12),
                      border: Border.all(
                        color: EOColors.orange.withValues(alpha: .55),
                      ),
                      borderRadius: BorderRadius.circular(EORadii.md),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: EOColors.orange),
                        SizedBox(width: EOSpacing.sm),
                        Expanded(
                          child: Text(
                            'Vista previa. Los perfiles, publicaciones y contadores '
                            'son ejemplos; no proceden de usuarios reales ni se '
                            'guardan en un servidor.',
                            style: EOTextStyles.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: EOSpacing.lg),
                  SegmentedButton<_CommunityTab>(
                    segments: const [
                      ButtonSegment(
                        value: _CommunityTab.following,
                        label: Text('Siguiendo'),
                        icon: Icon(Icons.people_outline),
                      ),
                      ButtonSegment(
                        value: _CommunityTab.explore,
                        label: Text('Explorar'),
                        icon: Icon(Icons.explore_outlined),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selection) {
                      setState(() => _tab = selection.first);
                    },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: EOSpacing.md),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: _tab == _CommunityTab.following
                          ? 'Buscar en Siguiendo'
                          : 'Buscar experiencias y descubrimientos',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: EOSpacing.lg),
                ],
              ),
            ),
          ),
          if (visiblePosts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(EOSpacing.xl),
                  child: Text(
                    'No hay coincidencias para esta búsqueda.',
                    textAlign: TextAlign.center,
                    style: EOTextStyles.body,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                EOSpacing.lg,
                0,
                EOSpacing.lg,
                EOSpacing.xxl,
              ),
              sliver: SliverList.separated(
                itemCount: visiblePosts.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: EOSpacing.md),
                itemBuilder: (context, index) {
                  final post = visiblePosts[index];
                  return _CommunityPostCard(
                    post: post,
                    liked: _likedPosts.contains(post.id),
                    saved: _savedPosts.contains(post.id),
                    onLike: () => setState(() {
                      if (!_likedPosts.add(post.id)) {
                        _likedPosts.remove(post.id);
                      }
                    }),
                    onSave: () => setState(() {
                      if (!_savedPosts.add(post.id)) {
                        _savedPosts.remove(post.id);
                      }
                    }),
                    onComment: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Los comentarios estarán disponibles al conectar la API.',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                EOSpacing.lg,
                0,
                EOSpacing.lg,
                EOSpacing.xxl,
              ),
              child: OutlinedButton.icon(
                onPressed: _showComposer,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Preparar una publicación'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPost {
  const _DemoPost({
    required this.id,
    required this.author,
    required this.handle,
    required this.activity,
    required this.age,
    required this.text,
    required this.place,
    required this.likes,
    required this.comments,
    required this.icon,
    this.routeName,
    this.routeMeta,
  });

  final String id;
  final String author;
  final String handle;
  final String activity;
  final String age;
  final String text;
  final String place;
  final int likes;
  final int comments;
  final IconData icon;
  final String? routeName;
  final String? routeMeta;
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.liked,
    required this.saved,
    required this.onLike,
    required this.onSave,
    required this.onComment,
  });

  final _DemoPost post;
  final bool liked;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: EOColors.surface,
          border: Border.all(color: EOColors.border),
          borderRadius: BorderRadius.circular(EORadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(EOSpacing.md),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: EOColors.greenSoft,
                    child: Icon(post.icon, color: EOColors.white),
                  ),
                  const SizedBox(width: EOSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.author, style: EOTextStyles.cardTitle),
                        const SizedBox(height: 2),
                        Text(
                          '${post.handle} · ${post.age}',
                          style: EOTextStyles.secondary,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Opciones de publicación',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: EOColors.surface,
                      builder: (context) => SafeArea(
                        child: ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: const Text('Denuncia y bloqueo se conectarán al backend'),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EOSpacing.md),
              child: Wrap(
                spacing: EOSpacing.sm,
                runSpacing: EOSpacing.sm,
                children: [
                  _Tag(label: post.activity, icon: post.icon),
                  _Tag(label: post.place, icon: Icons.place_outlined),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(EOSpacing.md),
              child: Text(post.text, style: EOTextStyles.body),
            ),
            if (post.routeName != null)
              Container(
                margin: const EdgeInsets.fromLTRB(
                  EOSpacing.md,
                  0,
                  EOSpacing.md,
                  EOSpacing.md,
                ),
                padding: const EdgeInsets.all(EOSpacing.md),
                decoration: BoxDecoration(
                  color: EOColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(EORadii.md),
                  border: Border.all(color: EOColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: EOColors.greenSoft,
                        borderRadius: BorderRadius.circular(EORadii.sm),
                      ),
                      child: const Icon(Icons.route_outlined, color: EOColors.white),
                    ),
                    const SizedBox(width: EOSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post.routeName!, style: EOTextStyles.cardTitle),
                          const SizedBox(height: 4),
                          Text(post.routeMeta!, style: EOTextStyles.secondary),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: EOColors.textTertiary),
                  ],
                ),
              ),
            const Divider(height: 1, color: EOColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EOSpacing.sm),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onLike,
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? EOColors.red : EOColors.textSecondary,
                    ),
                    label: Text('${post.likes + (liked ? 1 : 0)}'),
                  ),
                  TextButton.icon(
                    onPressed: onComment,
                    icon: const Icon(Icons.mode_comment_outlined),
                    label: Text('${post.comments}'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: saved ? 'Quitar de guardados' : 'Guardar publicación',
                    onPressed: onSave,
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      color: saved ? EOColors.green : EOColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EOSpacing.sm,
          vertical: EOSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: EOColors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: EOColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: EOColors.textSecondary),
            const SizedBox(width: EOSpacing.xs),
            Text(label, style: EOTextStyles.secondary),
          ],
        ),
      );
}
