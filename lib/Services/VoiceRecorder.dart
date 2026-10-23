import 'dart:io';
import 'dart:typed_data';

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

  /// Stops and returns what was recorded, or null if there is nothing.
  Future<VoiceClip?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();
}

/// [VoiceRecorder] over the `record` package.
///
/// Mono, 16 kHz, 32 kbit/s AAC: speech, not music. That is intelligible to the
/// model in three languages and keeps three minutes to well under a megabyte,
/// so the upload stays quick on a mobile connection.
class RecordPackageRecorder implements VoiceRecorder {
  RecordPackageRecorder();

  AudioRecorder? _recorder;
  String? _path;
  DateTime? _startedAt;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  @override
  Future<bool> ensurePermission() => _rec.hasPermission();

  @override
  Future<void> start() async {
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
    _startedAt = DateTime.now();
  }

  @override
  Future<VoiceClip?> stop() async {
    final started = _startedAt;
    final stopped = await _rec.stop();
    final path = stopped ?? _path;
    _path = null;
    _startedAt = null;
    if (path == null) return null;

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final seconds = started == null
          ? 0
          : DateTime.now().difference(started).inSeconds;
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
    _startedAt = null;
    try {
      await _rec.stop();
    } catch (_) {
      // Already stopped.
    }
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // See stop().
      }
    }
  }
}
