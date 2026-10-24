import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ua = {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'};

class Channel {
  final String name, url, group, logo;
  const Channel(this.name, this.url, {this.group = 'Sin grupo', this.logo = ''});

  Map<String, dynamic> toJson() => {'n': name, 'u': url, 'g': group, 'l': logo};
  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        j['n'] ?? '',
        j['u'] ?? '',
        group: j['g'] ?? 'Sin grupo',
        logo: j['l'] ?? '',
      );
}

enum ListType { url, text, xtream }

class IptvList {
  final String id, name, source, user, pass;
  final ListType type;
  const IptvList({
    required this.id,
    required this.name,
    required this.type,
    this.source = '',
    this.user = '',
    this.pass = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'source': source,
        'user': user,
        'pass': pass,
      };
  factory IptvList.fromJson(Map<String, dynamic> j) => IptvList(
        id: j['id'],
        name: j['name'],
        type: ListType.values.byName(j['type']),
        source: j['source'] ?? '',
        user: j['user'] ?? '',
        pass: j['pass'] ?? '',
      );
}

/// Parser M3U / M3U8 (top-level para poder usar compute()).
List<Channel> parseM3u(String text) {
  final out = <Channel>[];
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  String? name, group, logo;
  for (final raw in const LineSplitter().convert(text)) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXTINF')) {
      final a = {
        for (final m in attr.allMatches(l)) m.group(1)!.toLowerCase(): m.group(2)!
      };
      final i = l.lastIndexOf(',');
      name = i >= 0 ? l.substring(i + 1).trim() : '';
      if (name.isEmpty) name = a['tvg-name'] ?? 'Canal';
      group = a['group-title'];
      logo = a['tvg-logo'];
    } else if (l.startsWith('#EXTGRP:')) {
      group = l.substring(8).trim();
    } else if (!l.startsWith('#')) {
      out.add(Channel(
        name ?? l.split('/').last,
        l,
        group: (group == null || group.isEmpty) ? 'Sin grupo' : group,
        logo: logo ?? '',
      ));
      name = group = logo = null;
    }
  }
  return out;
}

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();

  late SharedPreferences _p;
  late Directory _dir;

  List<IptvList> lists = [];
  List<Channel> favorites = [];
  List<Channel> channels = [];
  String? activeId;
  bool loading = false;
  String? error;

  IptvList? get active {
    for (final l in lists) {
      if (l.id == activeId) return l;
    }
    return null;
  }

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _dir = await getApplicationSupportDirectory();
    await Directory('${_dir.path}/lists').create(recursive: true);
    await Directory('${_dir.path}/cache').create(recursive: true);
    lists = (jsonDecode(_p.getString('lists') ?? '[]') as List)
        .map((e) => IptvList.fromJson(e))
        .toList();
    favorites = (jsonDecode(_p.getString('favs') ?? '[]') as List)
        .map((e) => Channel.fromJson(e))
        .toList();
    activeId = _p.getString('active');
    final a = active;
    if (a != null) load(a);
  }

  Future<void> _save() async {
    await _p.setString('lists', jsonEncode(lists.map((e) => e.toJson()).toList()));
    await _p.setString('favs', jsonEncode(favorites.map((e) => e.toJson()).toList()));
    if (activeId != null) {
      await _p.setString('active', activeId!);
    } else {
      await _p.remove('active');
    }
  }

  // ---------- Listas ----------

  /// Para ListType.text, [source] es el contenido M3U completo.
  Future<void> addList({
    required String name,
    required ListType type,
    required String source,
    String user = '',
    String pass = '',
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    if (type == ListType.text) {
      await File('${_dir.path}/lists/$id.m3u').writeAsString(source);
    }
    final l = IptvList(
      id: id,
      name: name,
      type: type,
      source: type == ListType.text ? '' : source,
      user: user,
      pass: pass,
    );
    lists.add(l);
    await select(l);
  }

  Future<void> select(IptvList l) async {
    activeId = l.id;
    await _save();
    await load(l);
  }

  Future<void> removeList(IptvList l) async {
    lists.removeWhere((e) => e.id == l.id);
    for (final f in [
      File('${_dir.path}/lists/${l.id}.m3u'),
      File('${_dir.path}/cache/${l.id}.json'),
    ]) {
      if (await f.exists()) await f.delete();
    }
    if (activeId == l.id) {
      activeId = lists.isEmpty ? null : lists.first.id;
      channels = [];
      error = null;
    }
    await _save();
    notifyListeners();
    final a = active;
    if (a != null) await load(a);
  }

  Future<void> load(IptvList l, {bool force = false}) async {
    loading = true;
    error = null;
    channels = [];
    notifyListeners();
    try {
      List<Channel> list;
      final cache = File('${_dir.path}/cache/${l.id}.json');
      if (l.type == ListType.text) {
        final txt = await File('${_dir.path}/lists/${l.id}.m3u').readAsString();
        list = await compute(parseM3u, txt);
      } else if (!force && await cache.exists()) {
        list = (jsonDecode(await cache.readAsString()) as List)
            .map((e) => Channel.fromJson(e))
            .toList();
      } else {
        list = l.type == ListType.url
            ? await compute(parseM3u, await _get(l.source))
            : await _xtream(l);
        await cache.writeAsString(jsonEncode(list.map((c) => c.toJson()).toList()));
      }
      if (activeId == l.id) channels = list;
      if (list.isEmpty) error = 'La lista no contiene canales';
    } catch (e) {
      error = 'No se pudo cargar la lista: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<String> _get(String url) async {
    final r = await http
        .get(Uri.parse(url.trim()), headers: _ua)
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  Future<List<Channel>> _xtream(IptvList l) async {
    var base = l.source.trim();
    if (!base.startsWith('http')) base = 'http://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    final api = '$base/player_api.php'
        '?username=${Uri.encodeComponent(l.user)}'
        '&password=${Uri.encodeComponent(l.pass)}';
    final cats = {
      for (final c in jsonDecode(await _get('$api&action=get_live_categories')) as List)
        '${c['category_id']}': '${c['category_name']}'
    };
    final streams = jsonDecode(await _get('$api&action=get_live_streams')) as List;
    return [
      for (final s in streams)
        Channel(
          '${s['name']}',
          '$base/live/${l.user}/${l.pass}/${s['stream_id']}.ts',
          group: cats['${s['category_id']}'] ?? 'Sin grupo',
          logo: '${s['stream_icon'] ?? ''}',
        )
    ];
  }

  // ---------- Favoritos ----------

  bool isFav(Channel c) => favorites.any((f) => f.url == c.url);

  Future<void> toggleFav(Channel c) async {
    if (isFav(c)) {
      favorites.removeWhere((f) => f.url == c.url);
    } else {
      favorites.add(c);
    }
    await _save();
    notifyListeners();
  }

  // ---------- Caché ----------

  Future<void> clearCache() async {
    final d = Directory('${_dir.path}/cache');
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final a = active;
    if (a != null) await load(a, force: true);
  }
}
