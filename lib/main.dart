// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'ai_server.dart'; // ← AI service

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood Pomodoro (AI)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const PomodoroPage(),
    );
  }
}

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});
  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  int mood = 7; // 1~10
  bool isRunning = false;
  bool isBreak = false;
  int left = 25 * 60; // default 25 min
  int completedSets = 0; // 4-set cycle
  Timer? timer;

  List<LogEntry> logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  int _focusSecondsByMood(int m) {
    if (m >= 8) return 30 * 60;
    if (m <= 3) return 15 * 60;
    return 25 * 60;
  }

  int get _breakSeconds => 5 * 60;

  void start() {
    if (isRunning) return;
    setState(() => isRunning = true);

    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (left <= 1) {
        t.cancel();
        setState(() => isRunning = false);

        if (!isBreak) {
          await _onFocusFinished();
          _startBreak();
        } else {
          isBreak = false;
          if (completedSets >= 4) {
            _snack('4 sets completed! Check your weekly achievements 🎉');
            completedSets = 0;
          }
          left = _focusSecondsByMood(mood);
          setState(() {});
        }
      } else {
        setState(() => left--);
      }
    });
  }

  void pause() {
    timer?.cancel();
    setState(() => isRunning = false);
  }

  void reset() {
    timer?.cancel();
    isRunning = false;
    isBreak = false;
    left = _focusSecondsByMood(mood);
    setState(() {});
  }

  void _startBreak() {
    isBreak = true;
    left = _breakSeconds;
    setState(() {});
    start();
  }

  Future<void> _onFocusFinished() async {
    if (completedSets < 4) completedSets++;

    final entry = LogEntry(
      date: DateTime.now().toIso8601String(),
      mood: mood,
      focusMinutes: _focusSecondsByMood(mood) ~/ 60,
      result: 'focus_done',
    );
    logs.insert(0, entry);
    await _saveLogs();

    _snack('Focus completed! Break started ☕');
    _showAIFeedbackDialog();
  }

  // ---------------- Save/Load ----------------
  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(logs.map((e) => e.toJson()).toList());
    await prefs.setString('logs', raw);
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('logs');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => logs = list);
    }
  }

  // ---------------- AI Feedback ----------------
  Future<void> _showAIFeedbackDialog() async {
    final recent = logs.take(5).map((e) => e.toJson()).toList();
    String feedback = 'Generating AI feedback...';

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          () async {
            final ai = AIService();
            final text = await ai.dailyPlan(mood: mood, logs: recent);
            if (mounted) setLocal(() => feedback = text);
          }();
          return AlertDialog(
            title: const Text('AI Feedback'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(child: Text(feedback)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- UI ----------------
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String get _mmss {
    final m = (left ~/ 60).toString().padLeft(2, '0');
    final s = (left % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _setDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final done = i < completedSets;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(done ? Icons.circle : Icons.circle_outlined, size: 14),
        );
      }),
    );
  }

  // Weekly stats
  Widget _weeklyStats() {
    if (logs.isEmpty) return const Text("No records yet");
    final now = DateTime.now();
    final thisWeek = logs.where((e) {
      final d = DateTime.tryParse(e.date);
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          (now.day - d.day).abs() < 7;
    }).toList();

    final totalMinutes =
        thisWeek.fold(0, (sum, e) => sum + (e.focusMinutes));
    final avgMood =
        (thisWeek.isEmpty ? 0 : thisWeek.fold(0, (s, e) => s + e.mood) ~/ thisWeek.length);

    return Column(
      children: [
        Text("Total focus this week: ${totalMinutes} minutes"),
        Text("Average mood score: $avgMood/10"),
        Text("Completed sets: ${thisWeek.length} reps"),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = isBreak ? 'Break' : 'Focus';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mood Pomodoro (AI)'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _setDots(),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Mood'),
                    Expanded(
                      child: Slider(
                        value: mood.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '$mood',
                        onChanged: isRunning || isBreak
                            ? null
                            : (v) {
                                setState(() {
                                  mood = v.round();
                                  left = _focusSecondsByMood(mood);
                                });
                              },
                      ),
                    ),
                    Text('$mood/10'),
                  ],
                ),
                Text(label, style: const TextStyle(fontSize: 20)),
                Text(_mmss,
                    style: const TextStyle(
                        fontSize: 64,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                        onPressed: isRunning ? null : start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Start")),
                    OutlinedButton.icon(
                        onPressed: isRunning ? pause : null,
                        icon: const Icon(Icons.pause),
                        label: const Text("Pause")),
                    TextButton.icon(
                        onPressed: reset,
                        icon: const Icon(Icons.restore),
                        label: const Text("Reset")),
                    OutlinedButton.icon(
                        onPressed: () => _showAIFeedbackDialog(),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text("AI Feedback")),
                  ],
                ),
                const SizedBox(height: 16),
                _weeklyStats(),
                Expanded(
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final e = logs[i];
                      return ListTile(
                        title: Text("Mood ${e.mood} • ${e.focusMinutes} min"),
                        subtitle: Text(e.date),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Model ----------------
class LogEntry {
  LogEntry({
    required this.date,
    required this.mood,
    required this.focusMinutes,
    required this.result,
  });

  String date;
  int mood;
  int focusMinutes;
  String result;

  Map<String, dynamic> toJson() =>
      {'date': date, 'mood': mood, 'focusMinutes': focusMinutes, 'result': result};

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
      date: j['date'] as String,
      mood: j['mood'] as int,
      focusMinutes: j['focusMinutes'] as int,
      result: j['result'] as String);
}
