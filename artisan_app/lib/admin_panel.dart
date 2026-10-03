import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ADMIN LOGO WRAPPER — 7 taps unlocks admin panel
// ═══════════════════════════════════════════════════════════════════════════
class AdminLogoWrapper extends StatefulWidget {
  final Widget child;
  const AdminLogoWrapper({super.key, required this.child});

  @override
  State<AdminLogoWrapper> createState() => _AdminLogoWrapperState();
}

class _AdminLogoWrapperState extends State<AdminLogoWrapper> {
  int _tapCount = 0;
  DateTime? _lastTap;

  void _onTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 1) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount++;

    if (_tapCount >= 7) {
      _tapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
      );
    } else if (_tapCount >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${7 - _tapCount} more taps to unlock 👑'),
          duration: const Duration(milliseconds: 800),
          backgroundColor: K.deepMaroon,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ADMIN PANEL
// ═══════════════════════════════════════════════════════════════════════════
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _vibration = 'default';
  String _sound = 'default';
  DateTime? _scheduledAt;
  bool _busy = false;
  String? _secret;

  static const String _base = 'https://kalak-shetra-ai.onrender.com';

  static const List<Map<String, String>> _vibes = [
    {'key': 'default', 'label': '🔔 Default'},
    {'key': 'single', 'label': '📳 Single'},
    {'key': 'double', 'label': '📳📳 Double'},
    {'key': 'triple', 'label': '📳📳📳 Triple'},
    {'key': 'heartbeat', 'label': '💓 Heartbeat'},
    {'key': 'long', 'label': '📳 Long'},
    {'key': 'none', 'label': '🔕 None'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSecret();
  }

  Future<void> _loadSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('admin_secret');
    if (s != null && s.isNotEmpty) setState(() => _secret = s);
  }

  Future<void> _promptSecret() async {
    final ctrl = TextEditingController(text: _secret ?? '');
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: K.cream,
        title: const Text('Admin Secret'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Paste your secret'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (entered != null && entered.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_secret', entered);
      setState(() => _secret = entered);
    }
  }

  Future<String?> _getMyToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _send({required bool testOnly}) async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      _snack('Fill title and body');
      return;
    }
    if (_secret == null || _secret!.isEmpty) {
      await _promptSecret();
      if (_secret == null || _secret!.isEmpty) return;
    }

    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'topic': 'all_users',
        'vibration': _vibration,
        'sound': _sound,
      };

      if (testOnly) {
        final token = await _getMyToken();
        if (token == null) {
          _snack('Could not get device token');
          setState(() => _busy = false);
          return;
        }
        body['token'] = token;
      }

      final res = await http.post(
        Uri.parse('$_base/notify?secret=$_secret'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final ok = jsonDecode(res.body)['ok'] == true;
        _snack(ok
            ? (testOnly ? '✅ Sent to your phone!' : '✅ Sent to all users!')
            : '⚠️ ${res.body}');
      } else {
        _snack('Failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule() async {
    if (_scheduledAt == null) {
      _snack('Pick a date & time first');
      return;
    }
    if (_secret == null || _secret!.isEmpty) {
      await _promptSecret();
      if (_secret == null || _secret!.isEmpty) return;
    }

    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/schedule?secret=$_secret'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _titleCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'topic': 'all_users',
          'send_at': _scheduledAt!.toUtc().toIso8601String(),
          'vibration': _vibration,
          'sound': _sound,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (res.statusCode == 200) {
        _snack('✅ Scheduled for ${_scheduledAt.toString().substring(0, 16)}');
      } else {
        _snack('Failed: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _snack(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
      backgroundColor: K.leaf,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: const Text('👑 Admin Panel'),
        backgroundColor: K.deepMaroon,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Set admin secret',
            onPressed: _promptSecret,
          ),
        ],
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_secret == null || _secret!.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.warning_amber, color: Colors.orange),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('Set your admin secret first')),
                      TextButton(
                        onPressed: _promptSecret,
                        child: const Text('Set'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              _lbl('Title'),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '🎉 Diwali sale starts now!',
                  prefixIcon: Icon(Icons.title, color: K.maroon),
                ),
              ),
              const SizedBox(height: 16),

              _lbl('Message body'),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Explore fresh festive picks from artisans',
                  prefixIcon: Icon(Icons.message, color: K.maroon),
                ),
              ),
              const SizedBox(height: 20),

              _lbl('Vibration'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _vibes.map((v) {
                  final selected = _vibration == v['key'];
                  return ChoiceChip(
                    label: Text(v['label']!,
                        style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _vibration = v['key']!),
                    selectedColor: K.maroon,
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : K.maroon,
                        fontWeight: FontWeight.w600),
                    backgroundColor: K.paper,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              _lbl('Sound'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Default',
                          style: TextStyle(fontSize: 13)),
                      value: 'default',
                      groupValue: _sound,
                      activeColor: K.maroon,
                      onChanged: (v) => setState(() => _sound = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Silent',
                          style: TextStyle(fontSize: 13)),
                      value: 'silent',
                      groupValue: _sound,
                      activeColor: K.maroon,
                      onChanged: (v) => setState(() => _sound = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _lbl('Schedule (optional)'),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _scheduledAt == null
                          ? 'Not scheduled'
                          : _scheduledAt.toString().substring(0, 16),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (_scheduledAt != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _scheduledAt = null),
                    ),
                  TextButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: const Text('Pick'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: _busy ? null : () => _send(testOnly: true),
                icon: const Icon(Icons.phone_android),
                label: const Text('Test on my phone',
                    style: TextStyle(fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: K.maroon,
                  side: BorderSide(
                      color: K.gold.withValues(alpha: 0.6), width: 1.5),
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _busy ? null : () => _send(testOnly: false),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('Send to ALL users',
                    style: TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 52)),
              ),
              const SizedBox(height: 10),

              ElevatedButton.icon(
                onPressed:
                    _busy || _scheduledAt == null ? null : _schedule,
                icon: const Icon(Icons.schedule),
                label: const Text('Schedule for later',
                    style: TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: K.leaf,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: K.maroon,
                fontSize: 14)),
      );
}