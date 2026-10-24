import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

import 'app_state.dart';
import 'player_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await AppState.i.init();
  await PlayerService.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Distortion Labs IPTV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0B0B),
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE53935)),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0B0B)),
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  void _add() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const AddListSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final st = AppState.i;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DISTORTION LABS',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('IPTV', style: TextStyle(fontSize: 11, letterSpacing: 4)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Limpiar caché',
              icon: const Icon(Icons.cleaning_services),
              onPressed: () async {
                await st.clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Caché limpiada')));
                }
              },
            ),
            IconButton(
                tooltip: 'Agregar lista',
                icon: const Icon(Icons.add),
                onPressed: _add),
          ],
          bottom: TabBar(controller: _tabs, tabs: const [
            Tab(text: 'Canales'),
            Tab(text: 'Favoritos'),
            Tab(text: 'Listas'),
          ]),
        ),
        body: TabBarView(controller: _tabs, children: [
          ChannelsView(source: st.channels, isMain: true, onAdd: _add),
          ChannelsView(source: st.favorites),
          _ListsTab(onAdd: _add, goChannels: () => _tabs.animateTo(0)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Canales

class ChannelsView extends StatefulWidget {
  final List<Channel> source;
  final bool isMain;
  final VoidCallback? onAdd;
  const ChannelsView({super.key, required this.source, this.isMain = false, this.onAdd});

  @override
  State<ChannelsView> createState() => _ChannelsViewState();
}

class _ChannelsViewState extends State<ChannelsView> {
  String q = '', group = 'Todos';

  @override
  Widget build(BuildContext context) {
    final st = AppState.i;
    if (widget.isMain) {
      if (st.loading) return const Center(child: CircularProgressIndicator());
      if (st.lists.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Aún no tienes listas'),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: widget.onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Agregar lista')),
          ]),
        );
      }
      if (st.error != null) {
        return Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text(st.error!)));
      }
    } else if (widget.source.isEmpty) {
      return const Center(child: Text('Sin favoritos todavía'));
    }

    final groups = widget.source.map((c) => c.group).toSet().toList()..sort();
    groups.insert(0, 'Todos');
    if (!groups.contains(group)) group = 'Todos';

    final list = widget.source
        .where((c) =>
            (group == 'Todos' || c.group == group) &&
            (q.isEmpty || c.name.toLowerCase().contains(q)))
        .toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Buscar canal',
            prefixIcon: Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => q = v.toLowerCase()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButton<String>(
          isExpanded: true,
          value: group,
          items: [
            for (final g in groups)
              DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))
          ],
          onChanged: (v) => setState(() => group = v ?? 'Todos'),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            final fav = st.isFav(c);
            return ListTile(
              dense: true,
              leading: SizedBox(
                width: 44,
                height: 44,
                child: c.logo.startsWith('http')
                    ? Image.network(c.logo,
                        fit: BoxFit.contain,
                        cacheWidth: 88,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv))
                    : const Icon(Icons.tv),
              ),
              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(c.group, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: Icon(fav ? Icons.star : Icons.star_border,
                    color: fav ? Colors.amber : null),
                onPressed: () => st.toggleFav(c),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PlayerScreen(channels: list, index: i)),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ----------------------------------------------------------------- Listas

class _ListsTab extends StatelessWidget {
  final VoidCallback onAdd, goChannels;
  const _ListsTab({required this.onAdd, required this.goChannels});

  @override
  Widget build(BuildContext context) {
    final st = AppState.i;
    if (st.lists.isEmpty) {
      return Center(
        child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Agregar lista')),
      );
    }
    const icons = {
      ListType.url: Icons.link,
      ListType.text: Icons.content_paste,
      ListType.xtream: Icons.dns,
    };
    return ListView(children: [
      for (final l in st.lists)
        ListTile(
          leading: Icon(icons[l.type]),
          title: Text(l.name),
          subtitle: Text(l.id == st.activeId ? 'Activa' : l.type.name),
          selected: l.id == st.activeId,
          onTap: () {
            st.select(l);
            goChannels();
          },
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (l.type != ListType.text)
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  st.activeId = l.id;
                  st.load(l, force: true);
                  goChannels();
                },
              ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('¿Eliminar "${l.name}"?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (ok == true) st.removeList(l);
              },
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------- Agregar lista

class AddListSheet extends StatefulWidget {
  const AddListSheet({super.key});
  @override
  State<AddListSheet> createState() => _AddListSheetState();
}

class _AddListSheetState extends State<AddListSheet> {
  int mode = 0; // 0 URL, 1 pegar, 2 archivo, 3 Xtream
  final name = TextEditingController();
  final url = TextEditingController();
  final text = TextEditingController();
  final host = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  String? fileText, fileName;
  bool busy = false;

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    setState(() {
      fileText = utf8.decode(bytes, allowMalformed: true);
      fileName = r!.files.single.name;
    });
  }

  Future<void> _save() async {
    final n = name.text.trim();
    final st = AppState.i;
    setState(() => busy = true);
    try {
      if (mode == 0) {
        if (url.text.trim().isEmpty) return _msg('Escribe la URL');
        await st.addList(
            name: n.isEmpty ? 'Lista URL' : n,
            type: ListType.url,
            source: url.text.trim());
      } else if (mode == 1) {
        if (text.text.trim().isEmpty) return _msg('Pega el contenido M3U');
        await st.addList(
            name: n.isEmpty ? 'Lista pegada' : n,
            type: ListType.text,
            source: text.text);
      } else if (mode == 2) {
        if (fileText == null) return _msg('Selecciona un archivo');
        await st.addList(
            name: n.isEmpty ? (fileName ?? 'Archivo') : n,
            type: ListType.text,
            source: fileText!);
      } else {
        if (host.text.trim().isEmpty || user.text.isEmpty || pass.text.isEmpty) {
          return _msg('Completa servidor, usuario y contraseña');
        }
        await st.addList(
          name: n.isEmpty ? 'Xtream ${host.text.trim()}' : n,
          type: ListType.xtream,
          source: host.text.trim(),
          user: user.text.trim(),
          pass: pass.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
          {int lines = 1, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [
            for (final (i, t) in ['URL', 'Pegar', 'Archivo', 'Xtream'].indexed)
              ChoiceChip(
                  label: Text(t),
                  selected: mode == i,
                  onSelected: (_) => setState(() => mode = i)),
          ]),
          _field(name, 'Nombre (opcional)'),
          if (mode == 0) _field(url, 'URL de la lista M3U / M3U8'),
          if (mode == 1) _field(text, 'Pega aquí el contenido M3U', lines: 6),
          if (mode == 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(fileName ?? 'Elegir archivo .m3u / .m3u8 / .txt'),
              ),
            ),
          if (mode == 3) ...[
            _field(host, 'Servidor (http://host:puerto)'),
            _field(user, 'Usuario'),
            _field(pass, 'Contraseña', obscure: true),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : _save,
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar y cargar'),
            ),
          ),
        ]),
      ),
    );
  }
}
