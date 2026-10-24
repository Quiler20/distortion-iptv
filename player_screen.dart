import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_state.dart';

/// Reproductor único + servicio en primer plano (permite pantalla apagada).
class PlayerService {
  static late final Player player;
  static late final VideoController video;
  static late final _Handler _handler;

  static Future<void> init() async {
    player = Player();
    video = VideoController(player);
    _handler = await AudioService.init(
      builder: () => _Handler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.distortionlabs.iptv.playback',
        androidNotificationChannelName: 'Reproducción',
        androidNotificationOngoing: true,
      ),
    );
  }

  static Future<void> play(Channel c) async {
    _handler.mediaItem.add(MediaItem(
      id: c.url,
      title: c.name,
      album: c.group,
      artUri: c.logo.startsWith('http') ? Uri.tryParse(c.logo) : null,
    ));
    await player.open(Media(c.url, httpHeaders: {
      'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
    }));
  }

  static Future<void> stop() => _handler.stop();
}

class _Handler extends BaseAudioHandler {
  final Player p;
  _Handler(this.p) {
    p.stream.playing.listen((_) => _emit());
    p.stream.buffering.listen((_) => _emit());
  }

  void _emit() => playbackState.add(PlaybackState(
        controls: [
          p.state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.stop},
        androidCompactActionIndices: const [0],
        processingState: p.state.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: p.state.playing,
      ));

  @override
  Future<void> play() => p.play();
  @override
  Future<void> pause() => p.pause();
  @override
  Future<void> stop() async {
    await p.stop();
    return super.stop();
  }
}

class PlayerScreen extends StatefulWidget {
  final List<Channel> channels;
  final int index;
  const PlayerScreen({super.key, required this.channels, required this.index});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const _fitNames = ['Ajustar', 'Llenar', 'Estirar'];

  final _key = GlobalKey<ScaffoldState>();
  late int _i;
  bool _ui = true, _locked = false, _audioOnly = false, _land = false;
  int _fit = 0;
  double _zoom = 1, _base = 1;
  Timer? _hide;

  Channel get _ch => widget.channels[_i];

  @override
  void initState() {
    super.initState();
    _i = widget.index;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.enable();
    PlayerService.play(_ch);
    _autoHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    PlayerService.stop();
    super.dispose();
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _ui = false);
    });
  }

  void _tap() {
    setState(() => _ui = !_ui);
    if (_ui) _autoHide();
  }

  void _go(int i) {
    if (i < 0 || i >= widget.channels.length) return;
    setState(() => _i = i);
    PlayerService.play(_ch);
    _autoHide();
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(0.5, 3.0));

  void _toggleAudioOnly() {
    setState(() => _audioOnly = !_audioOnly);
    // En modo audio dejamos que la pantalla se apague sola.
    _audioOnly ? WakelockPlus.disable() : WakelockPlus.enable();
    _autoHide();
  }

  void _rotate() {
    _land = !_land;
    SystemChrome.setPreferredOrientations(_land
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _autoHide();
  }

  @override
  Widget build(BuildContext context) {
    final fav = AppState.i.isFav(_ch);
    return Scaffold(
      key: _key,
      backgroundColor: Colors.black,
      endDrawer: _locked
          ? null
          : Drawer(
              width: 320,
              backgroundColor: const Color(0xF2101010),
              child: SafeArea(
                child: _ChannelMenu(
                  channels: widget.channels,
                  current: _i,
                  onPick: (i) {
                    Navigator.pop(context);
                    _go(i);
                  },
                ),
              ),
            ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onScaleStart: (_) => _base = _zoom,
        onScaleUpdate: (d) {
          if (!_locked && d.pointerCount > 1) _setZoom(_base * d.scale);
        },
        child: Stack(children: [
          Positioned.fill(
            child: _audioOnly
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.headphones, size: 64, color: Colors.white38),
                      const SizedBox(height: 12),
                      Text(_ch.name,
                          style: const TextStyle(color: Colors.white54, fontSize: 18)),
                    ]),
                  )
                : Transform.scale(
                    scale: _zoom,
                    child: Video(
                      controller: PlayerService.video,
                      fit: _fits[_fit],
                      controls: NoVideoControls,
                    ),
                  ),
          ),
          StreamBuilder<bool>(
            stream: PlayerService.player.stream.buffering,
            initialData: true,
            builder: (_, s) => s.data == true
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          ),
          if (_ui && !_locked) ..._controls(fav),
          if (_ui && _locked)
            Align(
              alignment: Alignment.topRight,
              child: SafeArea(
                child: GestureDetector(
                  onLongPress: () {
                    setState(() => _locked = false);
                    _autoHide();
                  },
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock, size: 18),
                      SizedBox(width: 6),
                      Text('Mantén pulsado para desbloquear',
                          style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _controls(bool fav) {
    const grad = [Colors.black87, Colors.transparent];
    return [
      // Barra superior
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: grad),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(_ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Favorito',
                icon: Icon(fav ? Icons.star : Icons.star_border,
                    color: fav ? Colors.amber : null),
                onPressed: () async {
                  await AppState.i.toggleFav(_ch);
                  if (mounted) setState(() {});
                  _autoHide();
                },
              ),
              IconButton(
                tooltip: 'Canales',
                icon: const Icon(Icons.list),
                onPressed: () => _key.currentState?.openEndDrawer(),
              ),
            ]),
          ),
        ),
      ),
      // Barra inferior
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: grad),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    icon: const Icon(Icons.skip_previous), onPressed: () => _go(_i - 1)),
                StreamBuilder<bool>(
                  stream: PlayerService.player.stream.playing,
                  initialData: true,
                  builder: (_, s) => IconButton(
                    iconSize: 40,
                    icon: Icon(s.data == true ? Icons.pause_circle : Icons.play_circle),
                    onPressed: () => PlayerService.player.playOrPause(),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.skip_next), onPressed: () => _go(_i + 1)),
                const SizedBox(width: 12),
                IconButton(
                    tooltip: 'Reducir',
                    icon: const Icon(Icons.zoom_out),
                    onPressed: () => _setZoom(_zoom - 0.25)),
                IconButton(
                    tooltip: 'Ampliar',
                    icon: const Icon(Icons.zoom_in),
                    onPressed: () => _setZoom(_zoom + 0.25)),
                IconButton(
                  tooltip: 'Ajuste: ${_fitNames[_fit]}',
                  icon: const Icon(Icons.aspect_ratio),
                  onPressed: () {
                    setState(() {
                      _fit = (_fit + 1) % _fits.length;
                      _zoom = 1;
                    });
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          duration: const Duration(seconds: 1),
                          content: Text(_fitNames[_fit])));
                  },
                ),
                IconButton(
                    tooltip: 'Girar',
                    icon: const Icon(Icons.screen_rotation),
                    onPressed: _rotate),
                IconButton(
                  tooltip: 'Solo audio / pantalla apagada',
                  icon: Icon(Icons.headphones,
                      color: _audioOnly ? Theme.of(context).colorScheme.primary : null),
                  onPressed: _toggleAudioOnly,
                ),
                IconButton(
                  tooltip: 'Bloquear pantalla',
                  icon: const Icon(Icons.lock_outline),
                  onPressed: () {
                    setState(() => _locked = true);
                    _autoHide();
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    ];
  }
}

class _ChannelMenu extends StatefulWidget {
  final List<Channel> channels;
  final int current;
  final void Function(int) onPick;
  const _ChannelMenu(
      {required this.channels, required this.current, required this.onPick});

  @override
  State<_ChannelMenu> createState() => _ChannelMenuState();
}

class _ChannelMenuState extends State<_ChannelMenu> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final idx = [
      for (var i = 0; i < widget.channels.length; i++)
        if (q.isEmpty || widget.channels[i].name.toLowerCase().contains(q)) i
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
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
      Expanded(
        child: ListView.builder(
          itemCount: idx.length,
          itemBuilder: (_, k) {
            final i = idx[k];
            final c = widget.channels[i];
            return ListTile(
              dense: true,
              selected: i == widget.current,
              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: AppState.i.isFav(c)
                  ? const Icon(Icons.star, size: 16, color: Colors.amber)
                  : null,
              onTap: () => widget.onPick(i),
            );
          },
        ),
      ),
    ]);
  }
}
