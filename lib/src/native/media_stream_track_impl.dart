import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

import '../helper.dart';
import 'event_channel.dart';
import 'utils.dart';

class MediaStreamTrackNative extends MediaStreamTrack {
  MediaStreamTrackNative(this._trackId, this._label, this._kind, this._enabled,
      this._peerConnectionId,
      [this.settings_ = const {}]);

  factory MediaStreamTrackNative.fromMap(
      Map<dynamic, dynamic> map, String peerConnectionId) {
    return MediaStreamTrackNative(map['id'], map['label'], map['kind'],
        map['enabled'], peerConnectionId, map['settings'] ?? {});
  }
  final String _trackId;
  final String _label;
  final String _kind;
  final String _peerConnectionId;
  final Map<Object?, Object?> settings_;

  // Tracks whose end the native side reports with an "onTrackEnded" event
  // (Linux portal screen shares, ended from the system's sharing indicator
  // or by closing the shared window). Weak, so an unused track can go.
  static final Map<String, WeakReference<MediaStreamTrackNative>> _endable =
      {};
  // One listener for the app's lifetime, like the event channel itself.
  // ignore: cancel_subscriptions
  static StreamSubscription<Map<String, dynamic>>? _endedSubscription;

  /// Fires [onEnded] when the native side reports that this track ended.
  void watchEnded() {
    _endable[_trackId] = WeakReference(this);
    _endedSubscription ??=
        FlutterWebRTCEventChannel.instance.handleEvents.stream.listen((data) {
      final map = data['onTrackEnded'];
      if (map is! Map) return;
      final trackId = map['trackId'];
      if (trackId is! String) return;
      final track = _endable.remove(trackId)?.target;
      track?.onEnded?.call();
    });
  }

  bool _enabled;

  bool _muted = false;

  String get peerConnectionId => _peerConnectionId;

  @override
  set enabled(bool enabled) {
    WebRTC.invokeMethod('mediaStreamTrackSetEnable', <String, dynamic>{
      'trackId': _trackId,
      'enabled': enabled,
      'peerConnectionId': _peerConnectionId
    });
    _enabled = enabled;

    if (kind == 'audio') {
      _muted = !enabled;
      muted ? onMute?.call() : onUnMute?.call();
    }
  }

  @override
  bool get enabled => _enabled;

  @override
  String get label => _label;

  @override
  String get kind => _kind;

  @override
  String get id => _trackId;

  @override
  bool get muted => _muted;

  @override
  Future<bool> hasTorch() => WebRTC.invokeMethod(
        'mediaStreamTrackHasTorch',
        <String, dynamic>{'trackId': _trackId},
      ).then((value) => value ?? false);

  @override
  Future<void> setTorch(bool torch) => WebRTC.invokeMethod(
        'mediaStreamTrackSetTorch',
        <String, dynamic>{'trackId': _trackId, 'torch': torch},
      );

  @override
  Future<bool> switchCamera() => Helper.switchCamera(this);

  Future<void> setZoom(double zoomLevel) => Helper.setZoom(this, zoomLevel);

  @Deprecated('Use Helper.setSpeakerphoneOn instead')
  @override
  void enableSpeakerphone(bool enable) async {
    return Helper.setSpeakerphoneOn(enable);
  }

  @override
  Future<ByteBuffer> captureFrame() async {
    var filePath = await getTemporaryDirectory();
    await WebRTC.invokeMethod(
      'captureFrame',
      <String, dynamic>{
        'trackId': _trackId,
        'peerConnectionId': _peerConnectionId,
        'path': '${filePath.path}/captureFrame.png'
      },
    );
    return File('${filePath.path}/captureFrame.png')
        .readAsBytes()
        .then((value) => value.buffer);
  }

  @override
  Future<void> applyConstraints([Map<String, dynamic>? constraints]) {
    if (constraints == null) return Future.value();

    var current = getConstraints();
    if (constraints.containsKey('volume') &&
        current['volume'] != constraints['volume']) {
      Helper.setVolume(constraints['volume'], this);
    }

    return Future.value();
  }

  @override
  Map<String, dynamic> getSettings() {
    return settings_.map((key, value) => MapEntry(key.toString(), value));
  }

  @override
  Future<void> dispose() async {
    return stop();
  }

  @override
  Future<void> stop() async {
    _endable.remove(_trackId);
    await WebRTC.invokeMethod(
      'trackDispose',
      <String, dynamic>{'trackId': _trackId},
    );
  }
}
