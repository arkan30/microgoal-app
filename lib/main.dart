// main.dart
// اپ میکروهدف - نسخه فلاتر (به‌روزرسانی کامل، منطبق با نسخه‌ی وب فعلی)
// این فایل رو داخل پروژه‌ی Flutter خودت، جایگزین lib/main.dart کن.
//
// قبل از اجرا، این پکیج‌ها رو به pubspec.yaml اضافه کن:
//   http: ^1.2.0
//   shared_preferences: ^2.2.2
// و بعد بزن: flutter pub get
//
// آدرس بک‌اند رو پایین (apiBase) با آدرس واقعی Vercel خودت عوض کن.
// روی شبیه‌ساز اندروید اگر بخوای از لوکال تست کنی: 10.0.2.2 به‌جای localhost

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiBase = 'https://microgoal-backend.vercel.app'; // آدرس واقعی خودتو اینجا بذار

class AppColors {
  static const bg = Color(0xFFFBF1EF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFFF8F6);
  static const text = Color(0xFF3A2C2E);
  static const textSoft = Color(0xFF7A6265);
  static const border = Color(0xFFEAD9D5);
  static const rose = Color(0xFFD98C93);
  static const roseDeep = Color(0xFFC36F77);
  static const sage = Color(0xFF8FA88C);
  static const sageDeep = Color(0xFF6E8A6A);
}

void main() => runApp(const MicroGoalApp());

class MicroGoalApp extends StatelessWidget {
  const MicroGoalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'میکروهدف',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bg,
        fontFamily: 'Vazirmatn',
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.rose),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const RootGate(),
    );
  }
}

// ==================== API ====================
class Api {
  static Future<http.Response> _withRetry(Future<http.Response> Function() request) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await request().timeout(const Duration(seconds: 15));
      } catch (e) {
        lastError = e;
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw Exception('اتصال به سرور ناموفق بود: $lastError');
  }

  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final r = await _withRetry(() => http.post(Uri.parse('$apiBase$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));
    final d = jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return d;
    throw Exception(d['error'] ?? 'خطای سرور');
  }

  static Future<Map<String, dynamic>> _put(String path, Map body) async {
    final r = await _withRetry(() => http.put(Uri.parse('$apiBase$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));
    final d = jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return d;
    throw Exception(d['error'] ?? 'خطای سرور');
  }

  static Future<dynamic> _get(String path) async {
    final r = await _withRetry(() => http.get(Uri.parse('$apiBase$path')));
    return jsonDecode(r.body);
  }

  static Future<void> _delete(String path) async {
    await _withRetry(() => http.delete(Uri.parse('$apiBase$path')));
  }

  static Future<Map<String, dynamic>> register(String email, String pass) =>
      _post('/register', {'email': email, 'password': pass});
  static Future<Map<String, dynamic>> login(String email, String pass) =>
      _post('/login', {'email': email, 'password': pass});

  static Future<String> getGestalt(int userId) async {
    final d = await _get('/users/$userId/gestalt');
    return d['gestalt_text'] ?? '';
  }
  static Future<void> saveGestalt(int userId, String text) =>
      _put('/users/$userId/gestalt', {'gestalt_text': text});

  static Future<List<dynamic>> getGoals(int userId) async { final r = await _get('/goals/$userId'); return r as List<dynamic>; }
  static Future<int> addGoal(int userId, String title, int position) async {
    final d = await _post('/goals', {'user_id': userId, 'title': title, 'position': position});
    return d['goalId'];
  }
  static Future<void> updateGoal(int goalId, String title) => _put('/goals/$goalId', {'title': title});
  static Future<void> deleteGoal(int goalId) => _delete('/goals/$goalId');

  static Future<List<dynamic>> getSubgoals(int goalId) async { final r = await _get('/subgoals/$goalId'); return r as List<dynamic>; }
  static Future<void> addSubgoal(int goalId, String text) =>
      _post('/subgoals', {'main_goal_id': goalId, 'text': text});
  static Future<void> toggleSubgoal(int subId, bool done) =>
      _put('/subgoals/$subId', {'is_done': done ? 1 : 0});
  static Future<void> editSubgoal(int subId, String text) =>
      _put('/subgoals/$subId', {'text': text});
  static Future<void> deleteSubgoal(int subId) => _delete('/subgoals/$subId');

  static Future<List<dynamic>> getNotes(int userId) async { final r = await _get('/notes/$userId'); return r as List<dynamic>; }
  static Future<void> saveNote(int userId, String date, String note, bool marked) =>
      _post('/notes', {'user_id': userId, 'date': date, 'note': note, 'is_marked': marked ? 1 : 0});

  static Future<Map<String, dynamic>> getProgress(int userId) async { final r = await _get('/progress/$userId'); return r as Map<String, dynamic>; }
}
// ==================== ورود خودکار ====================
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}
class _RootGateState extends State<RootGate> {
  int? userId;
  String? email;
  bool checked = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('user_id');
    final em = prefs.getString('user_email');
    setState(() {
      userId = id;
      email = em;
      checked = true;
    });
  }

  void _onLoggedIn(int id, String em) => setState(() { userId = id; email = em; });
  void _onLoggedOut() => setState(() { userId = null; email = null; });

  @override
  Widget build(BuildContext context) {
    if (!checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.rose)));
    }
    if (userId == null) {
      return AuthScreen(onLoggedIn: _onLoggedIn);
    }
    return HomeScreen(userId: userId!, email: email!, onLogout: _onLoggedOut);
  }
}

// ==================== ثبت‌نام / ورود ====================
class AuthScreen extends StatefulWidget {
  final void Function(int userId, String email) onLoggedIn;
  const AuthScreen({super.key, required this.onLoggedIn});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool remember = true;
  String? msg;

  Future<void> _submit() async {
    setState(() => msg = null);
    try {
      if (isLogin) {
        final d = await Api.login(emailCtrl.text.trim(), passCtrl.text);
        if (remember) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', d['userId']);
          await prefs.setString('user_email', emailCtrl.text.trim());
        }
        widget.onLoggedIn(d['userId'], emailCtrl.text.trim());
      } else {
        await Api.register(emailCtrl.text.trim(), passCtrl.text);
        setState(() { isLogin = true; msg = 'ثبت‌نام موفق بود، حالا وارد شوید'; });
      }
    } catch (e) {
      setState(() => msg = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🌱 میکروهدف',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _tabButton('ورود', isLogin, () => setState(() => isLogin = true))),
                  const SizedBox(width: 8),
                  Expanded(child: _tabButton('ثبت‌نام', !isLogin, () => setState(() => isLogin = false))),
                ]),
                const SizedBox(height: 18),
                TextField(controller: emailCtrl, decoration: _inputDeco('ایمیل')),
                const SizedBox(height: 12),
                TextField(controller: passCtrl, obscureText: true, decoration: _inputDeco('رمز عبور')),
                if (isLogin) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Checkbox(value: remember, activeColor: AppColors.rose,
                        onChanged: (v) => setState(() => remember = v ?? true)),
                    const Text('مرا به خاطر بسپار', style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                  ]),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _submit,
                    child: Text(isLogin ? 'ورود' : 'ساخت حساب', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (msg != null)
                  Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(msg!, style: const TextStyle(color: AppColors.textSoft, fontSize: 13))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.rose : AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textSoft, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

InputDecoration _inputDeco(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.surfaceTint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.rose)),
    );

// ==================== مدل‌ها ====================
class GoalData {
  int? id;
  int position;
  String title = '';
  List<SubGoalData> subgoals = [];
  GoalData(this.position, {this.id});
}
class SubGoalData {
  final int id;
  String text;
  bool done;
  SubGoalData(this.id, this.text, this.done);
}
class NoteData {
  int? id;
  String date;
  String note;
  bool marked;
  NoteData({this.id, required this.date, this.note = '', this.marked = false});
}

// ==================== صفحه اصلی ====================
class HomeScreen extends StatefulWidget {
  final int userId;
  final String email;
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.userId, required this.email, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      GoalsTab(userId: widget.userId),
      CalendarTab(userId: widget.userId),
      ProgressTab(userId: widget.userId),
      const AboutAppTab(),
      const AboutMeTab(),
    ];
  }

  Future<void> _doLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('🌱 میکروهدف', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: AppColors.textSoft), onPressed: _doLogout),
        ],
      ),
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: AppColors.roseDeep,
        unselectedItemColor: AppColors.textSoft,
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'خانه'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'تقویم'),
          BottomNavigationBarItem(icon: Icon(Icons.donut_large), label: 'پیشرفت'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'درباره اپ'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'درباره من'),
        ],
      ),
    );
  }
}

// ==================== تب اهداف (گشتالت + اهداف + ریزهدف‌ها) ====================
class GoalsTab extends StatefulWidget {
  final int userId;
  const GoalsTab({super.key, required this.userId});
  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab> {
  final gestaltCtrl = TextEditingController();
  bool gestaltExpanded = false;
  Timer? gestaltTimer;
  List<GoalData> goals = [1, 2, 3, 4].map((p) => GoalData(p)).toList();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        Api.getGestalt(widget.userId),
        Api.getGoals(widget.userId),
      ]);
      gestaltCtrl.text = results[0] as String;
      final serverGoals = results[1] as List<dynamic>;

      final List<GoalData> matched = [];
      for (final sg in serverGoals) {
        final pos = sg['position'];
        GoalData existing;
        final found = goals.where((x) => x.position == pos);
        if (found.isNotEmpty) {
          existing = found.first;
        } else {
          existing = GoalData(pos);
          goals.add(existing);
        }
        existing.id = sg['id'];
        existing.title = sg['title'];
        matched.add(existing);
      }
      final subResults = await Future.wait(matched.map((g) => Api.getSubgoals(g.id!)));
      for (int i = 0; i < matched.length; i++) {
        matched[i].subgoals = subResults[i].map((s) => SubGoalData(s['id'], s['text'], s['is_done'] == 1)).toList();
      }
      goals.sort((a, b) => a.position.compareTo(b.position));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در اتصال به سرور: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  void _onGestaltChanged(String v) {
    gestaltTimer?.cancel();
    gestaltTimer = Timer(const Duration(milliseconds: 700), () {
      Api.saveGestalt(widget.userId, v);
    });
  }

  Future<void> _saveGoalTitle(GoalData g, String title) async {
    if (title.trim().isEmpty) return;
    try {
      if (g.id == null) {
        g.id = await Api.addGoal(widget.userId, title, g.position);
      } else {
        await Api.updateGoal(g.id!, title);
      }
      g.title = title;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ذخیره هدف: $e')));
    }
  }

  Future<void> _deleteGoal(GoalData g) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف هدف'),
        content: const Text('این هدف و همه‌ی ریزهدف‌هایش حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (g.id != null) await Api.deleteGoal(g.id!);
      setState(() => goals.remove(g));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در حذف هدف: $e')));
    }
  }

  Future<void> _addSubgoal(GoalData g, String text) async {
    if (g.id == null || text.trim().isEmpty) return;
    try {
      await Api.addSubgoal(g.id!, text);
      final subs = await Api.getSubgoals(g.id!);
      setState(() => g.subgoals = subs.map((s) => SubGoalData(s['id'], s['text'], s['is_done'] == 1)).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در افزودن ریزهدف: $e')));
    }
  }

  Future<void> _toggleSub(SubGoalData s) async {
    try {
      await Api.toggleSubgoal(s.id, !s.done);
      setState(() => s.done = !s.done);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در به‌روزرسانی: $e')));
    }
  }
  Future<void> _deleteSub(GoalData g, SubGoalData s) async {
    try {
      await Api.deleteSubgoal(s.id);
      setState(() => g.subgoals.remove(s));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در حذف: $e')));
    }
  }

  Future<void> _editSubgoalDialog(SubGoalData s) async {
    final ctrl = TextEditingController(text: s.text);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ویرایش ریزهدف'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('ذخیره')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await Api.editSubgoal(s.id, result.trim());
      setState(() => s.text = result.trim());
    }
  }

  void _addNewGoalSlot() {
    final nextPos = goals.map((g) => g.position).fold<int>(0, (a, b) => a > b ? a : b) + 1;
    setState(() => goals.add(GoalData(nextPos)));
  }

  String _goalLabel(int pos) {
    const names = {1: 'اول', 2: 'دوم', 3: 'سوم', 4: 'چهارم'};
    return names[pos] != null ? 'هدف ${names[pos]}' : 'هدف شماره $pos';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.rose));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // گشتالت من
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('گشتالت من', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
            const SizedBox(height: 6),
            const Text('یک توضیح اجمالی از تصویر کلی اهدافتان بنویسید.', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: gestaltCtrl,
              maxLines: gestaltExpanded ? 8 : 1,
              onChanged: _onGestaltChanged,
              decoration: InputDecoration(
                filled: true, fillColor: AppColors.surfaceTint,
                hintText: 'مثلاً: امسال می‌خواهم روی چند مسیر اصلی زندگی‌ام کار کنم...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => gestaltExpanded = !gestaltExpanded),
              child: Text(gestaltExpanded ? 'دیدن کمتر' : 'دیدن بیشتر', style: const TextStyle(color: AppColors.roseDeep)),
            ),
          ]),
        ),

        const Text('اهداف اصلی شما', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
        const SizedBox(height: 10),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.72,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: goals.map((g) => _goalCard(g)).toList(),
        ),

        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(14),
                side: const BorderSide(color: AppColors.rose)),
            onPressed: _addNewGoalSlot,
            child: const Icon(Icons.add, color: AppColors.roseDeep),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _goalCard(GoalData g) {
    final titleCtrl = TextEditingController(text: g.title);
    final subCtrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: titleCtrl,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              decoration: InputDecoration(border: InputBorder.none, hintText: 'عنوان ${_goalLabel(g.position)}…', isDense: true),
              onSubmitted: (v) => _saveGoalTitle(g, v),
              onEditingComplete: () => _saveGoalTitle(g, titleCtrl.text),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textSoft),
            onPressed: () => _deleteGoal(g),
          ),
        ]),
        Expanded(
          child: ListView(
            children: g.subgoals.map((s) => _subgoalRow(g, s)).toList(),
          ),
        ),
        Row(children: [
          Expanded(child: TextField(controller: subCtrl, style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(hintText: 'ریزهدف جدید…', isDense: true))),
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.rose, size: 20),
            onPressed: () { _addSubgoal(g, subCtrl.text); subCtrl.clear(); },
          ),
        ]),
      ]),
    );
  }

  Widget _subgoalRow(GoalData g, SubGoalData s) {
    return Row(children: [
      GestureDetector(
        onTap: () => _toggleSub(s),
        child: Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.done ? AppColors.sage : Colors.transparent,
            border: Border.all(color: AppColors.rose, width: 2),
          ),
          child: s.done ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: GestureDetector(
          onDoubleTap: () => _editSubgoalDialog(s),
          child: Text(s.text, style: TextStyle(
              fontSize: 12,
              decoration: s.done ? TextDecoration.lineThrough : null,
              color: s.done ? AppColors.textSoft : AppColors.text)),
        ),
      ),
      GestureDetector(onTap: () => _deleteSub(g, s), child: const Icon(Icons.close, size: 14, color: AppColors.textSoft)),
    ]);
  }
}

// ==================== تب تقویم ====================
class CalendarTab extends StatefulWidget {
  final int userId;
  const CalendarTab({super.key, required this.userId});
  @override
  State<CalendarTab> createState() => _CalendarTabState();
}
class _CalendarTabState extends State<CalendarTab> {
  DateTime calDate = DateTime.now();
  Map<String, NoteData> notesCache = {};
  bool loading = true;

  final List<String> dayNames = ['ی', 'د', 'س', 'چ', 'پ', 'ج', 'ش'];
  final List<String> monthNames = ['ژانویه','فوریه','مارس','آوریل','مه','ژوئن','ژوئیه','اوت','سپتامبر','اکتبر','نوامبر','دسامبر'];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadNotes() async {
    try {
      final notes = await Api.getNotes(widget.userId);
      notesCache = {};
      for (final n in notes) {
        notesCache[n['date']] = NoteData(id: n['id'], date: n['date'], note: n['note'] ?? '', marked: n['is_marked'] == 1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در بارگذاری تقویم: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openNoteDialog(String dateStr, NoteData? existing) async {
    final ctrl = TextEditingController(text: existing?.note ?? '');
    bool marked = existing?.marked ?? false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text('یادداشت برای $dateStr'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, maxLines: 3),
          Row(children: [
            Checkbox(value: marked, onChanged: (v) => setD(() => marked = v ?? false)),
            const Text('این روز را با تیک سبز علامت بزن'),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      )),
    );
    if (result == true) {
      await Api.saveNote(widget.userId, dateStr, ctrl.text, marked);
      await _loadNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.rose));
    final y = calDate.year, m = calDate.month;
    final firstDay = DateTime(y, m, 1).weekday % 7; // 0=Sunday alignment approx
    final daysInMonth = DateTime(y, m + 1, 0).day;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => calDate = DateTime(y, m - 1, 1))),
          Text('${monthNames[m - 1]} $y', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => calDate = DateTime(y, m + 1, 1))),
        ]),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ...dayNames.map((n) => Center(child: Text(n, style: const TextStyle(fontSize: 11, color: AppColors.textSoft)))),
            ...List.generate(firstDay, (_) => const SizedBox()),
            ...List.generate(daysInMonth, (i) {
              final day = i + 1;
              final dateStr = _fmt(DateTime(y, m, day));
              final note = notesCache[dateStr];
              return GestureDetector(
                onTap: () => _openNoteDialog(dateStr, note),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: (note?.marked ?? false) ? AppColors.sage.withValues(alpha: 0.25) : AppColors.surfaceTint,
                    border: Border.all(color: (note?.marked ?? false) ? AppColors.sage : AppColors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(children: [
                    Center(child: Text('$day', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                    if (note?.marked ?? false)
                      const Positioned(bottom: 1, left: 1, child: Icon(Icons.check_circle, size: 10, color: AppColors.sageDeep)),
                  ]),
                ),
              );
            }),
          ],
        ),
      ]),
    );
  }
}

// ==================== تب پیشرفت ====================
class ProgressTab extends StatefulWidget {
  final int userId;
  const ProgressTab({super.key, required this.userId});
  @override
  State<ProgressTab> createState() => _ProgressTabState();
}
class _ProgressTabState extends State<ProgressTab> {
  int total = 0, done = 0, percent = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.getProgress(widget.userId);
      total = d['total_subgoals'];
      done = d['completed_subgoals'];
      percent = d['progress_percent'];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در بارگذاری پیشرفت: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.rose));
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 140, height: 140,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: percent / 100, strokeWidth: 12, backgroundColor: AppColors.border, color: AppColors.rose),
            Text('$percent٪', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _statBox('$total', 'کل ریزهدف‌ها'),
          const SizedBox(width: 30),
          _statBox('$done', 'تکمیل‌شده'),
        ]),
      ]),
    );
  }

  Widget _statBox(String num, String label) => Column(children: [
        Text(num, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.roseDeep)),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
      ]);
}

// ==================== درباره اپ ====================
class AboutAppTab extends StatelessWidget {
  const AboutAppTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: const [
      Text('به میکروهدف خوش آمدید', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
      SizedBox(height: 14),
      Text(
        'این ابزار برای کسانی ساخته شده که می‌خوان با یک دید گشتالتی به اهدافشون نگاه کنن؛ یعنی قبل از هر چیز، یک تصویر کلی و اجمالی از خواسته‌هاشون بسازن، و بعد رفته‌رفته این تصویر را با جزئیات کامل کنن.',
        style: TextStyle(color: AppColors.textSoft, height: 1.8),
      ),
      SizedBox(height: 16),
      Text('مثال نقاشی اسب', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
      SizedBox(height: 6),
      Text(
        'فرض کنید می‌خواهید یک اسب نقاشی کنید. ابتدا طرح کلی را می‌کشید، سپس جزئیات را اضافه می‌کنید. اگر خسته شوید، باز هم یک اسب کامل دارید — نه یک جزئیات ناتمام.',
        style: TextStyle(color: AppColors.textSoft, height: 1.8),
      ),
      SizedBox(height: 16),
      Text('چرا اینجا ثبت ساعت مطالعه وجود ندارد؟', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
      SizedBox(height: 6),
      Text('چون تمرکز روی زمان، شما را از خودِ هدف دور می‌کند.', style: TextStyle(color: AppColors.textSoft, height: 1.8)),
    ]);
  }
}

// ==================== درباره من ====================
class AboutMeTab extends StatelessWidget {
  const AboutMeTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: const [
      Text('ارکان محمودی', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
      SizedBox(height: 14),
      Text(
        'شغل اصلی من مشاور مدرسه است. علاقه‌مندم به دانش‌آموزان و هرکسی که می‌خواهد با یک مسیر روشن به اهدافش برسد کمک کنم. رویکرد اصلی من در طراحی این ابزار، رویکرد گشتالتی است.',
        style: TextStyle(color: AppColors.textSoft, height: 1.8),
      ),
      SizedBox(height: 16),
      Text('شغل: مشاور مدرسه', style: TextStyle(color: AppColors.textSoft)),
      SizedBox(height: 6),
      Text('شماره تماس: (به‌زودی تکمیل می‌شود)', style: TextStyle(color: AppColors.textSoft)),
      SizedBox(height: 6),
      Text('تلگرام: (به‌زودی تکمیل می‌شود)', style: TextStyle(color: AppColors.textSoft)),
    ]);
  }
}
