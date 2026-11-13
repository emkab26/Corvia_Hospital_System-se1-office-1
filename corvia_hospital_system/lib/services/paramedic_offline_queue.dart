import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as cipher;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _derive(List<Object> input) {
  final kdf = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  kdf.init(pc.Pbkdf2Parameters(base64Decode(input[1] as String), 210000, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(input[0] as String)));
}

/// Only encrypted pending clinical writes are persisted. The passphrase/key is
/// never stored; it must be supplied after an authenticated workspace opens.
class ParamedicOfflineQueue {
  cipher.Key? _key;
  String? _salt, _storageKey, _scope;
  List<Map<String, dynamic>> _items = [];
  int _generation = 0;
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  bool get unlocked => _key != null;
  Future<void> unlock(String scope, String passphrase) async {
    final generation = _generation;
    if (passphrase.length < 12) {
      throw StateError(
          'Use at least 12 characters for your offline passphrase.');
    }
    final storageKey = 'corvia_ems_queue_${sha256.convert(utf8.encode(scope))}';
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(storageKey);
    final envelope = stored == null ? null : jsonDecode(stored) as Map;
    final salt =
        envelope?['salt'] as String? ?? cipher.IV.fromSecureRandom(32).base64;
    final key = cipher.Key(await compute(_derive, [passphrase, salt]));
    if (generation != _generation) {
      key.bytes.fillRange(0, key.bytes.length, 0);
      throw StateError('Workspace locked while unlocking the queue.');
    }
    List<Map<String, dynamic>> items = [];
    if (envelope != null) {
      try {
        final text = cipher.Encrypter(cipher.AES(key, mode: cipher.AESMode.gcm))
            .decrypt(cipher.Encrypted.fromBase64(envelope['data'] as String),
                iv: cipher.IV.fromBase64(envelope['iv'] as String),
                associatedData: Uint8List.fromList(utf8.encode(scope)));
        items = (jsonDecode(text) as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      } catch (_) {
        throw StateError(
            'Offline passphrase is incorrect or the encrypted queue is damaged. Existing records were preserved.');
      }
    }
    _key = key;
    _salt = salt;
    _scope = scope;
    _storageKey = storageKey;
    _items = items;
    await _save();
  }

  Future<void> _save() async {
    if (_key == null) throw StateError('Unlock the offline queue first.');
    final iv = cipher.IV.fromSecureRandom(12);
    final data = cipher.Encrypter(cipher.AES(_key!, mode: cipher.AESMode.gcm))
        .encrypt(jsonEncode(_items),
            iv: iv, associatedData: Uint8List.fromList(utf8.encode(_scope!)));
    final ok = await (await SharedPreferences.getInstance()).setString(
        _storageKey!,
        jsonEncode({
          'version': 1,
          'salt': _salt,
          'iv': iv.base64,
          'data': data.base64
        }));
    if (!ok) {
      throw StateError(
          'Could not persist the offline record. Keep the form open.');
    }
  }

  Future<void> add(
      String op, String action, Map<String, dynamic> payload) async {
    if (!unlocked) {
      throw StateError('Unlock the offline queue before working offline.');
    }
    if (_items.any((r) => r['op'] == op)) return;
    final record = {
      'op': op,
      'action': action,
      'payload': payload,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
      'state': 'Pending',
      'attempts': 0
    };
    _items.add(record);
    try {
      await _save();
    } catch (_) {
      _items.remove(record);
      rethrow;
    }
  }

  Future<void> remove(String op) async {
    final before = List<Map<String, dynamic>>.from(_items);
    _items.removeWhere((r) => r['op'] == op);
    try {
      await _save();
    } catch (_) {
      _items = before;
      rethrow;
    }
  }

  Future<void> fail(String op, String error) async {
    final r = _items.firstWhere((r) => r['op'] == op);
    r['state'] = 'Failed';
    r['attempts'] = (r['attempts'] as int) + 1;
    r['error'] = error;
    await _save();
  }

  void lock() {
    _generation++;
    _key?.bytes.fillRange(0, _key!.bytes.length, 0);
    _key = null;
    _salt = null;
    _scope = null;
    _storageKey = null;
    _items = [];
  }
}
