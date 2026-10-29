import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

/// One finished recording, in memory only.
///
/// The audio is never kept: [RecordPackageRecorder] deletes its temporary file
/// the moment it has read it, and the bytes live only as long as the screen
/// holding them needs for a retry.
class VoiceClip {
  const VoiceClip({
    required this.bytes,
    required this.mimeType,
    required this.seconds,
  });

  final Uint8List bytes;

  /// What the phone says it recorded, sent on so the server knows how to read it.
  final String mimeType;

  /// How long the guide was recording, in whole seconds.
  final int seconds;
}

/// The microphone, behind a seam so a screen can be tested without one.
abstract class VoiceRecorder {
  /// The real one, except in tests.
  static VoiceRecorder instance = RecordPackageRecorder();

  /// Swaps the microphone in tests.
  static void useForTests(VoiceRecorder? recorder) =>
      instance = recorder ?? RecordPackageRecorder();

  /// Whether the guide has allowed the microphone, asking the system the first
  /// time. False means he said no — the caller says how to turn it back on.
  Future<bool> ensurePermission();

  /// Starts recording. Throws if the microphone cannot be opened.
  Future<void> start();

  /// Holds the recording without ending it. The time while paused is not counted.
  Future<void> pause();

  /// Carries on after [pause].
  Future<void> resume();

  /// Stops and returns what was recorded, or null if there is nothing. Works the same
  /// from a recording that is running and one that is paused.
  Future<VoiceClip?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();
}

/// A recorder that can say how loud the voice is, for the live waveform. Separate from [VoiceRecorder] so a test's own recorder
/// need not implement it; the screen asks `recorder is VoiceLevels`.
abstract class VoiceLevels {
  /// Loudness readings, 0 (silence) to 1 (loud), about every 80 ms while recording. Ends when the recording does.
  Stream<double> get levels;
}

/// [VoiceRecorder] over the `record` package.
///
/// Mono, 16 kHz, 32 kbit/s AAC: speech, not music. That is intelligible to the
/// model in three languages and keeps three minutes to well under a megabyte,
/// so the upload stays quick on a mobile connection.
class RecordPackageRecorder implements VoiceRecorder, VoiceLevels {
  RecordPackageRecorder();

  AudioRecorder? _recorder;
  String? _path;

  /// Recorded time so far, NOT counting a pause: the server checks the length it is told
  /// against the three-minute limit, and a guide who paused for ten minutes has not
  /// recorded ten minutes.
  Duration _recorded = Duration.zero;
  DateTime? _segmentStart;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  /// The microphone's level in decibels (about -50 for a quiet room to 0 for loud), as 0..1.
  @override
  Stream<double> get levels => _rec.onAmplitudeChanged(const Duration(milliseconds: 80)).map((a) => ((a.current + 50) / 50).clamp(0.0, 1.0));

  @override
  Future<bool> ensurePermission() => _rec.hasPermission();

  @override
  Future<void> start() async {
    if (kIsWeb) {
      // In a browser there are no files: the page records with MediaRecorder (webm / opus, which the server accepts) and hands back a blob URL.
      await _rec.start(const RecordConfig(encoder: AudioEncoder.opus, numChannels: 1), path: '');
      _path = 'web';
      _recorded = Duration.zero;
      _segmentStart = DateTime.now();
      return;
    }
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}voice_note_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _path = path;
    _recorded = Duration.zero;
    _segmentStart = DateTime.now();
  }

  /// Adds the running segment to [_recorded].
  void _closeSegment() {
    final s = _segmentStart;
    if (s != null) _recorded += DateTime.now().difference(s);
    _segmentStart = null;
  }

  @override
  Future<void> pause() async {
    if (_segmentStart == null) return;
    await _rec.pause();
    _closeSegment();
  }

  @override
  Future<void> resume() async {
    if (_segmentStart != null || _path == null) return;
    await _rec.resume();
    _segmentStart = DateTime.now();
  }

  @override
  Future<VoiceClip?> stop() async {
    _closeSegment();
    final seconds = _recorded.inSeconds;
    final stopped = await _rec.stop();
    final path = stopped ?? _path;
    _path = null;
    _recorded = Duration.zero;
    if (path == null) return null;

    if (kIsWeb) {
      // `path` is the blob URL of the recording: read it once, and it is gone with the page.
      try {
        final bytes = await http.readBytes(Uri.parse(path));
        if (bytes.isEmpty) return null;
        return VoiceClip(bytes: bytes, mimeType: 'audio/webm', seconds: seconds);
      } catch (_) {
        return null;
      }
    }

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return VoiceClip(bytes: bytes, mimeType: 'audio/mp4', seconds: seconds);
    } finally {
      // Not kept, whatever happened above.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A temp file we could not remove is cleaned up with the cache.
      }
    }
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    _segmentStart = null;
    _recorded = Duration.zero;
    try {
      await _rec.stop();
    } catch (_) {
      // Already stopped.
    }
    if (path != null && !kIsWeb) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // See stop().
      }
    }
  }
}
