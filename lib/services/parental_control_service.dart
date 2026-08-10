import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';

class ParentalControlService extends ChangeNotifier {
  ParentalControlService._();

  static final ParentalControlService instance = ParentalControlService._();

  static const _enabledKey = 'parental_enabled_v1';
  static const _pinHashKey = 'parental_pin_hash_v1';
  static const _hideAdultKey = 'parental_hide_adult_v1';
  static const _unlockMinutesKey = 'parental_unlock_minutes_v1';
  static const _manualGroupsKey = 'parental_manual_groups_v1';
  static const _allowedGroupsKey = 'parental_allowed_groups_v1';

  bool _initialized = false;
  bool _enabled = false;
  bool _hideAdult = false;
  int _unlockMinutes = 15;
  String? _pinHash;
  DateTime? _unlockedUntil;
  Timer? _unlockTimer;
  Set<String> _manualGroups = <String>{};
  Set<String> _allowedGroups = <String>{};

  bool get enabled => _enabled;
  bool get hideAdult => _hideAdult;
  int get unlockMinutes => _unlockMinutes;
  bool get pinConfigured => _pinHash != null && _pinHash!.isNotEmpty;

  bool get isUnlocked {
    if (!_enabled) return true;
    final until = _unlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get isLocked => _enabled && !isUnlocked;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _pinHash = prefs.getString(_pinHashKey);
    _hideAdult = prefs.getBool(_hideAdultKey) ?? false;
    _unlockMinutes = prefs.getInt(_unlockMinutesKey) ?? 15;
    _manualGroups = (prefs.getStringList(_manualGroupsKey) ?? const <String>[])
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();
    _allowedGroups = (prefs.getStringList(_allowedGroupsKey) ?? const <String>[])
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();
    _initialized = true;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('El PIN debe tener exactamente 4 números.');
    }
    final prefs = await SharedPreferences.getInstance();
    _pinHash = _hashPin(pin);
    _enabled = true;
    _clearUnlockTimer();
    await prefs.setString(_pinHashKey, _pinHash!);
    await prefs.setBool(_enabledKey, true);
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final hash = _pinHash;
    return hash != null && hash == _hashPin(pin);
  }

  Future<bool> unlock(String pin) async {
    if (!verifyPin(pin)) return false;
    _clearUnlockTimer();
    final duration = Duration(minutes: _unlockMinutes);
    _unlockedUntil = DateTime.now().add(duration);
    _unlockTimer = Timer(duration, () {
      _unlockedUntil = null;
      _unlockTimer = null;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void lockNow() {
    _clearUnlockTimer();
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = value && pinConfigured;
    if (!_enabled) _clearUnlockTimer();
    await prefs.setBool(_enabledKey, _enabled);
    notifyListeners();
  }

  Future<void> setHideAdult(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _hideAdult = value;
    await prefs.setBool(_hideAdultKey, value);
    notifyListeners();
  }

  Future<void> setUnlockMinutes(int value) async {
    final normalized = switch (value) {
      5 => 5,
      30 => 30,
      60 => 60,
      _ => 15,
    };
    final prefs = await SharedPreferences.getInstance();
    _unlockMinutes = normalized;
    await prefs.setInt(_unlockMinutesKey, normalized);
    if (_enabled && isUnlocked) {
      _clearUnlockTimer();
    }
    notifyListeners();
  }

  bool isProtectedGroup(String? group) {
    final normalized = _normalize(group ?? '');
    if (normalized.isEmpty) return false;
    if (_allowedGroups.contains(normalized)) return false;
    if (_manualGroups.contains(normalized)) return true;
    return _looksAdultText(normalized);
  }

  bool isProtectedChannel(Channel channel) {
    final normalizedGroup = _normalize(channel.group ?? '');
    if (normalizedGroup.isNotEmpty && _allowedGroups.contains(normalizedGroup)) {
      return false;
    }
    if (isProtectedGroup(channel.group)) return true;
    return _looksAdultText(_normalize(channel.name));
  }

  bool canShowChannel(Channel channel) {
    if (!_enabled || isUnlocked) return true;
    return !isProtectedChannel(channel);
  }

  List<String> visibleGroups(Iterable<String> groups) {
    if (!_enabled || isUnlocked || !_hideAdult) {
      return groups.toList(growable: false);
    }
    return groups
        .where((group) => !isProtectedGroup(group))
        .toList(growable: false);
  }

  Future<void> setGroupProtected(String group, bool protected) async {
    final normalized = _normalize(group);
    if (normalized.isEmpty) return;
    if (protected) {
      _allowedGroups.remove(normalized);
      _manualGroups.add(normalized);
    } else {
      _manualGroups.remove(normalized);
      _allowedGroups.add(normalized);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_manualGroupsKey, _manualGroups.toList()..sort());
    await prefs.setStringList(_allowedGroupsKey, _allowedGroups.toList()..sort());
    notifyListeners();
  }

  void _clearUnlockTimer() {
    _unlockTimer?.cancel();
    _unlockTimer = null;
    _unlockedUntil = null;
  }

  static String _hashPin(String pin) {
    return sha256.convert(utf8.encode('tv-full-parental:$pin')).toString();
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  static bool _looksAdultText(String value) {
    if (value.isEmpty) return false;
    const markers = <String>[
      'adult',
      'adulto',
      'adultos',
      'xxx',
      '18+',
      '+18',
      'porno',
      'porn',
      'erotic',
      'erotico',
      'erótica',
      'erotica',
      'onlyfans',
      'only fans',
      'only fan',
      'hentai',
      'playboy',
    ];
    return markers.any(value.contains);
  }
}
