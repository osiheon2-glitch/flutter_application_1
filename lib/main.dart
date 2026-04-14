import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async';
import 'dart:convert';

final FlutterLocalNotificationsPlugin notiPlugin = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notiPlugin.initialize(settings: initSettings);
}

Future<void> showNotification(String title, String body) async {
  const androidDetail = AndroidNotificationDetails(
    'focusbody_channel',
    'FocusBody 알림',
    channelDescription: 'FocusBody AI 알림',
    importance: Importance.high,
    priority: Priority.high,
  );
  const detail = NotificationDetails(android: androidDetail);
  await notiPlugin.show(id: 0, title: title, body: body, notificationDetails: detail);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  await initNotifications();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: LoginPage(),
    );
  }
}

// ================= 로그인 =================

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  TextEditingController nameController = TextEditingController();

  Future<void> login() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', nameController.text);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("FocusBody AI", style: TextStyle(fontSize: 28)),
              SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: "이름 입력"),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: login,
                child: Text("시작하기"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ================= 메인 =================

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {

  String userName = "";
  bool isPremium = false;

  double sleep = 6;
  double stress = 5;
  double study = 2;
  double exercise = 1;
  double sit = 5;

  bool showDetail = false;

  double fatigue = 0;
  String statusText = "";
  Color statusColor = Colors.green;
  Color _prevStatusColor = Colors.green;
  List<String> aiAdviceList = [];
  String aiMessage = "";
  String timerRecommendText = "";
  int timerRecommendSeconds = 0;

  // 애니메이션
  late AnimationController _glowController;
  late AnimationController _colorController;
  late Animation<double> _glowAnimation;
  late Animation<Color?> _colorAnimation;

  List<double> fatigueHistory = [];

  int adCount = 0;

  // 배너 광고
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  // 전면 광고
  InterstitialAd? _interstitialAd;

  int totalTime = 0; // 타이머 전체 시간 (초)
  int currentTime = 0; // 타이머 남은 시간 (초)
  Timer? timer;

  // 일일 기록
  List<Map<String, dynamic>> dailyLogs = [];

  // 오늘의 목표/루틴
  List<Map<String, dynamic>> goals = [];
  String lastGoalDate = '';

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _colorController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _colorAnimation = ColorTween(begin: Colors.green, end: Colors.green)
        .animate(CurvedAnimation(parent: _colorController, curve: Curves.easeInOut));

    loadData();
    loadDailyLogs();
    loadGoals();
    _loadBannerAd();
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      // 테스트 광고 ID - 배포 시 실제 ID로 교체하세요
      adUnitId: 'ca-app-pub-3940256099942544/1033173712',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadInterstitialAd(); // 다음 광고 미리 로드
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
        },
      ),
    );
  }

  void _showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialAd = null;
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      // 테스트 광고 ID - 배포 시 실제 광고 단위 ID로 교체하세요
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _isBannerLoaded = false;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    timer?.cancel();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _glowController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  // ================= 데이터 저장 =================

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble('sleep', sleep);
    await prefs.setDouble('stress', stress);
    await prefs.setDouble('study', study);
    await prefs.setDouble('exercise', exercise);
    await prefs.setDouble('sit', sit);

    await prefs.setStringList(
      'fatigueHistory',
      fatigueHistory.map((e) => e.toString()).toList(),
    );
  }

  // ================= 데이터 불러오기 =================

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      userName = prefs.getString('userName') ?? "사용자";

      sleep = prefs.getDouble('sleep') ?? 6;
      stress = prefs.getDouble('stress') ?? 5;
      study = prefs.getDouble('study') ?? 2;
      exercise = prefs.getDouble('exercise') ?? 1;
      sit = prefs.getDouble('sit') ?? 5;

      fatigueHistory = (prefs.getStringList('fatigueHistory') ?? [])
          .map((e) => double.parse(e))
          .toList();
    });
  }

  // ================= 일일 기록 =================

  String get todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> loadDailyLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('dailyLogs');
    if (raw != null) {
      setState(() {
        dailyLogs = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    }
  }

  Future<void> saveDailyLog() async {
    final record = {
      'date': todayKey,
      'sleep': sleep,
      'stress': stress,
      'fatigue': double.parse(fatigue.toStringAsFixed(1)),
      'study': study,
      'exercise': exercise,
      'sit': sit,
    };

    // 같은 날짜가 있으면 덮어쓰기
    dailyLogs.removeWhere((log) => log['date'] == todayKey);
    dailyLogs.insert(0, record);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dailyLogs', jsonEncode(dailyLogs));

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$todayKey 기록이 저장되었습니다!")),
    );
  }

  Future<void> deleteDailyLog(int index) async {
    dailyLogs.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dailyLogs', jsonEncode(dailyLogs));
    setState(() {});
  }

  void showDailyLogHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40, height: 4,
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text("기록 히스토리", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Expanded(
                    child: dailyLogs.isEmpty
                        ? Center(child: Text("저장된 기록이 없습니다", style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: dailyLogs.length,
                            itemBuilder: (context, index) {
                              final log = dailyLogs[index];
                              final f = (log['fatigue'] as num).toDouble();
                              Color fColor = f < 3 ? Colors.green : (f < 6 ? Colors.yellow : Colors.red);
                              return Container(
                                margin: EdgeInsets.only(bottom: 10),
                                padding: EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(log['date'], style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: fColor.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                "피로도 ${f.toStringAsFixed(1)}",
                                                style: TextStyle(color: fColor, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: Text("기록 삭제"),
                                                    content: Text("${log['date']} 기록을 삭제할까요?"),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text("취소")),
                                                      TextButton(
                                                        onPressed: () {
                                                          Navigator.pop(ctx);
                                                          Navigator.pop(context); // bottom sheet 닫기
                                                          deleteDailyLog(index);
                                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                                            SnackBar(content: Text("${log['date']} 기록이 삭제되었습니다")),
                                                          );
                                                        },
                                                        child: Text("삭제", style: TextStyle(color: Colors.red)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                              child: Icon(Icons.delete_outline, color: Colors.red[300], size: 22),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        _logChip("수면", "${(log['sleep'] as num).toStringAsFixed(1)}h"),
                                        _logChip("스트레스", "${(log['stress'] as num).toStringAsFixed(1)}"),
                                        _logChip("공부", "${(log['study'] as num).toStringAsFixed(1)}h"),
                                        _logChip("운동", "${(log['exercise'] as num).toStringAsFixed(1)}h"),
                                        _logChip("앉은시간", "${(log['sit'] as num).toStringAsFixed(1)}h"),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _logChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label ", style: TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ================= 목표/루틴 =================

  Future<void> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('goalsDate') ?? '';
    final raw = prefs.getString('goals');

    // 날짜가 바뀌면 체크만 초기화, 목표 항목은 유지
    if (savedDate != todayKey && raw != null) {
      final parsed = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
      );
      for (var g in parsed) {
        g['done'] = false;
      }
      goals = parsed;
      await prefs.setString('goalsDate', todayKey);
      await prefs.setString('goals', jsonEncode(goals));
    } else if (raw != null) {
      goals = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }

    setState(() {});
  }

  Future<void> saveGoals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('goals', jsonEncode(goals));
    await prefs.setString('goalsDate', todayKey);
  }

  void toggleGoal(int index) {
    setState(() {
      goals[index]['done'] = !(goals[index]['done'] as bool);
    });
    saveGoals();
  }

  void addGoal(String title) {
    if (title.trim().isEmpty) return;
    setState(() {
      goals.add({'title': title.trim(), 'done': false});
    });
    saveGoals();
  }

  void deleteGoal(int index) {
    setState(() {
      goals.removeAt(index);
    });
    saveGoals();
  }

  void showAddGoalDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("목표 추가"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: "예: 물 3번 마시기"),
          onSubmitted: (v) {
            addGoal(v);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("취소")),
          TextButton(
            onPressed: () {
              addGoal(controller.text);
              Navigator.pop(ctx);
            },
            child: Text("추가"),
          ),
        ],
      ),
    );
  }

  List<String> generateAIGoals() {
    List<String> suggestions = [];

    // 수면 기반
    if (sleep < 5) {
      suggestions.add("오늘 밤 7시간 이상 수면하기");
      suggestions.add("오후 2시 이후 카페인 금지");
    } else if (sleep < 7) {
      suggestions.add("낮잠 20분 자기");
      suggestions.add("밤 11시 전에 잠자리 들기");
    } else {
      suggestions.add("수면 루틴 유지하기");
    }

    // 스트레스 기반
    if (stress > 7) {
      suggestions.add("5분 호흡 명상하기");
      suggestions.add("좋아하는 음악 1곡 듣기");
      suggestions.add("감사한 일 3가지 적기");
    } else if (stress > 4) {
      suggestions.add("10분 산책하기");
      suggestions.add("심호흡 3회 하기");
    }

    // 운동 기반
    if (exercise < 1) {
      suggestions.add("스트레칭 1회 하기");
      suggestions.add("30분 이상 걷기");
      suggestions.add("계단 이용하기");
    } else if (exercise < 3) {
      suggestions.add("운동 30분 하기");
    }

    // 앉은시간 기반
    if (sit > 6) {
      suggestions.add("50분마다 일어나서 움직이기");
      suggestions.add("서서 일하기 30분");
    }

    // 공부 기반
    if (study > 4) {
      suggestions.add("뽀모도로 타이머 활용하기 (25분+5분)");
      suggestions.add("눈 운동하기 (20-20-20 규칙)");
    }

    // 기본 건강 목표
    suggestions.add("물 3잔 이상 마시기");
    suggestions.add("10분 집중 타임 갖기");
    suggestions.add("간식 대신 과일 먹기");
    suggestions.add("SNS 30분 이내로 제한하기");
    suggestions.add("잠자기 전 스마트폰 내려놓기");

    // 이미 추가된 목표 제외
    final existingTitles = goals.map((g) => g['title'] as String).toSet();
    suggestions = suggestions.where((s) => !existingTitles.contains(s)).toList();

    return suggestions;
  }

  void showAIGoalDialog() {
    final suggestions = generateAIGoals();
    final selected = List<bool>.filled(suggestions.length, false);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("AI 목표 추천"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "현재 상태를 분석해서 추천합니다.\n추가할 목표를 선택하세요.",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        itemBuilder: (context, i) {
                          return CheckboxListTile(
                            dense: true,
                            title: Text(suggestions[i], style: TextStyle(fontSize: 14)),
                            value: selected[i],
                            activeColor: Colors.deepPurpleAccent,
                            onChanged: (v) {
                              setDialogState(() {
                                selected[i] = v ?? false;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text("취소")),
                TextButton(
                  onPressed: () {
                    for (int i = 0; i < suggestions.length; i++) {
                      if (selected[i]) {
                        addGoal(suggestions[i]);
                      }
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text("추가", style: TextStyle(color: Colors.deepPurpleAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int get completedGoals => goals.where((g) => g['done'] == true).length;

  Widget buildGoalCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("오늘의 목표", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (goals.isNotEmpty)
                    Text(
                      "$completedGoals / ${goals.length}",
                      style: TextStyle(
                        fontSize: 14,
                        color: completedGoals == goals.length && goals.isNotEmpty
                            ? Colors.greenAccent
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: showAIGoalDialog,
                    child: Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 22),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: showAddGoalDialog,
                    child: Icon(Icons.add_circle_outline, color: Colors.deepPurpleAccent),
                  ),
                ],
              ),
            ],
          ),
          if (goals.isNotEmpty) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goals.isEmpty ? 0 : completedGoals / goals.length,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  completedGoals == goals.length ? Colors.greenAccent : Colors.deepPurpleAccent,
                ),
              ),
            ),
          ],
          SizedBox(height: 10),
          if (goals.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("+ 버튼을 눌러 오늘의 목표를 추가하세요", style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            ...goals.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              final done = g['done'] as bool;
              return Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => toggleGoal(i),
                      child: Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: done ? Colors.greenAccent : Colors.white38,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        g['title'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? Colors.white38 : Colors.white,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => deleteGoal(i),
                      child: Icon(Icons.close, color: Colors.white24, size: 20),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ================= 타이머 =================

  void startTimer(int seconds) {
    timer?.cancel();
    setState(() {
      totalTime = seconds;
      currentTime = seconds;
    });
    timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (currentTime <= 0) {
        t.cancel();
        setState(() {});
        showNotification("⏱ 타이머 종료!", "설정한 시간이 끝났습니다. 스트레칭을 해보세요!");
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("타이머 종료!"),
            content: Text("시간이 끝났습니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text("OK")),
            ],
          ),
        );
      } else {
        setState(() {
          currentTime--;
        });
      }
    });
  }

  void resetTimer() {
    timer?.cancel();
    setState(() {
      currentTime = 0;
      totalTime = 0;
    });
  }

  double get timerProgress {
    if (totalTime == 0) return 0;
    return (totalTime - currentTime) / totalTime;
  }

  // ================= AI 계산 (세부화) =================

  void calculateAI() {
    fatigue = ((10 - sleep) * 0.4)
        + (stress * 0.4)
        + (study * 0.1)
        + (sit * 0.1)
        - (exercise * 0.2);

    fatigue = fatigue.clamp(0, 10).toDouble();

    fatigueHistory.insert(0, fatigue);
    if (fatigueHistory.length > 7) fatigueHistory.removeLast();

    // 상태 판정
    if (fatigue < 3) {
      statusText = "🔥 최고의 컨디션";
      statusColor = Colors.green;
    } else if (fatigue < 6) {
      statusText = "🙂 무난한 상태";
      statusColor = Colors.yellow;
    } else {
      statusText = "⚠ 휴식 필요";
      statusColor = Colors.red;
    }

    // 세부 AI 추천
    aiAdviceList = [];

    // 수면 기반 추천
    if (sleep < 5) {
      aiAdviceList.add("😴 수면 부족! 오늘은 일찍 자세요 (목표: 7시간 이상)");
      aiAdviceList.add("☕ 카페인은 오후 2시 이전에만 섭취하세요");
    } else if (sleep < 7) {
      aiAdviceList.add("🛏 수면이 약간 부족합니다. 낮잠 20분을 추천합니다");
    } else {
      aiAdviceList.add("✅ 수면 상태 양호! 좋은 컨디션입니다");
    }

    // 스트레스 기반 추천
    if (stress > 7) {
      aiAdviceList.add("🧘 스트레스가 높습니다! 5분 호흡 명상을 해보세요");
      aiAdviceList.add("🎵 차분한 음악을 들으며 긴장을 풀어보세요");
    } else if (stress > 4) {
      aiAdviceList.add("🚶 가벼운 산책으로 기분 전환을 해보세요");
    } else {
      aiAdviceList.add("😊 스트레스 관리가 잘 되고 있어요!");
    }

    // 운동 기반 추천
    if (exercise < 1) {
      aiAdviceList.add("🏃 오늘 운동이 부족합니다! 최소 30분 활동을 추천합니다");
      aiAdviceList.add("🤸 간단한 스트레칭부터 시작해보세요");
    } else if (exercise >= 3) {
      aiAdviceList.add("💪 운동량 충분! 근육 회복을 위해 수분을 섭취하세요");
    }

    // 앉은시간 기반 추천
    if (sit > 8) {
      aiAdviceList.add("🪑 오래 앉아있었습니다! 매 50분마다 5분 서서 움직이세요");
      aiAdviceList.add("🦵 하체 스트레칭이 필요합니다 (허벅지, 종아리)");
    } else if (sit > 5) {
      aiAdviceList.add("🧍 앉은 시간이 많습니다. 서서 일하기를 시도해보세요");
    }

    // 공부 기반 추천
    if (study > 8) {
      aiAdviceList.add("📚 공부량이 많습니다! 뽀모도로 기법 (25분 집중 + 5분 휴식)을 활용하세요");
      aiAdviceList.add("👀 눈 피로 방지: 20분마다 20초간 먼 곳을 바라보세요");
    } else if (study > 4) {
      aiAdviceList.add("📖 적당한 공부량입니다. 집중력 유지를 위해 물을 마시세요");
    }

    // 종합 추천
    if (fatigue >= 7) {
      aiAdviceList.add("🚨 피로도가 매우 높습니다! 오늘은 무리하지 마세요");
      aiAdviceList.add("💧 수분 섭취와 가벼운 간식을 추천합니다");
    }

    // 색상 애니메이션
    _colorAnimation = ColorTween(begin: _prevStatusColor, end: statusColor)
        .animate(CurvedAnimation(parent: _colorController, curve: Curves.easeInOut));
    _colorController.forward(from: 0);
    _prevStatusColor = statusColor;

    // 타이머 AI 추천
    if (fatigue >= 7) {
      timerRecommendText = "😮‍💨 피로가 높아요! 5분 휴식 추천";
      timerRecommendSeconds = 5 * 60;
    } else if (fatigue >= 5 && stress > 5) {
      timerRecommendText = "🧘 스트레스 해소! 10분 명상 추천";
      timerRecommendSeconds = 10 * 60;
    } else if (study > 6) {
      timerRecommendText = "📖 공부량이 많아요! 25분 집중 + 휴식 추천";
      timerRecommendSeconds = 25 * 60;
    } else if (sit > 6) {
      timerRecommendText = "🧍 오래 앉았어요! 5분 스트레칭 추천";
      timerRecommendSeconds = 5 * 60;
    } else if (fatigue < 3) {
      timerRecommendText = "🔥 컨디션 최고! 25분 집중 타이머 추천";
      timerRecommendSeconds = 25 * 60;
    } else {
      timerRecommendText = "⏱ 10분 집중 타이머 추천";
      timerRecommendSeconds = 10 * 60;
    }

    // AI 한줄 메시지
    aiMessage = _generateAIMessage();

    // 푸시 알림 발송
    showNotification(
      "FocusBody AI 분석 완료",
      "피로도: ${fatigue.toStringAsFixed(1)} - $statusText",
    );

    // 3회마다 전면 광고 표시
    adCount++;
    if (adCount % 3 == 0) {
      _showInterstitialAd();
    }

    saveData();
    setState(() {});
  }

  String _generateAIMessage() {
    // 피로도 높음 + 스트레스 높음
    if (fatigue >= 7 && stress > 7) {
      final msgs = [
        "오늘은 무리하지 않는 게 좋아요. 자신을 돌보세요 🫂",
        "많이 지쳤죠? 오늘 하루는 쉬어가도 괜찮아요 🌙",
        "당신의 몸이 쉬고 싶다고 말하고 있어요. 들어주세요 💤",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 피로도 높음
    if (fatigue >= 7) {
      final msgs = [
        "오늘은 무리하지 않는 게 좋아요 🙂",
        "천천히 가도 괜찮아요. 쉬는 것도 실력이에요 🍃",
        "에너지를 아껴두세요. 내일의 나를 위해 🔋",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 수면 부족
    if (sleep < 5) {
      final msgs = [
        "잠이 많이 부족해요. 오늘 밤은 일찍 자보는 건 어때요? 😴",
        "수면이 부족하면 모든 게 더 힘들어져요. 일찍 쉬세요 🌜",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 스트레스 높음
    if (stress > 7) {
      final msgs = [
        "스트레스가 높네요. 잠깐 눈을 감고 심호흡 해볼까요? 🧘",
        "마음이 무거운 날이군요. 좋아하는 노래 한 곡 어때요? 🎵",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 운동 부족 + 오래 앉음
    if (exercise < 1 && sit > 6) {
      final msgs = [
        "오래 앉아있었네요. 잠깐 일어나서 기지개 한번 켜볼까요? 🙆",
        "몸이 굳어있을 거예요. 가벼운 스트레칭 추천해요! 🤸",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 무난한 상태
    if (fatigue >= 3 && fatigue < 6) {
      final msgs = [
        "괜찮은 하루예요! 이 페이스 유지해봐요 👍",
        "나쁘지 않은 컨디션이에요. 한 가지만 더 신경 쓰면 완벽! ✨",
        "오늘도 잘 하고 있어요. 물 한 잔 마시는 건 어때요? 💧",
      ];
      return msgs[DateTime.now().microsecond % msgs.length];
    }
    // 최고 컨디션
    final msgs = [
      "컨디션 최고! 오늘 하고 싶은 일에 도전해보세요 🔥",
      "에너지가 넘치는 날이에요! 멋진 하루 보내세요 🚀",
      "완벽한 컨디션이에요. 오늘의 당신은 무적! 💪",
      "최고의 상태네요! 이 기분 오래 간직하세요 😊",
    ];
    return msgs[DateTime.now().microsecond % msgs.length];
  }

  // ================= 그래프 =================

  Widget buildChart() {
    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          titlesData: FlTitlesData(show: false),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: fatigueHistory.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value);
              }).toList(),
              isCurved: true,
              barWidth: 3,
              color: statusColor,
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI 위젯 =================

  Widget slider(String title, double value, double max, Function(double) onChanged){
    return Column(
      children: [
        Text("$title : ${value.toStringAsFixed(1)}"),
        Slider(
          value: value,
          max: max,
          onChanged: (v){
            onChanged(v);
            saveData();
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget actionButton(String text){
    return ElevatedButton(
      onPressed: (){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$text 시작!")),
        );
      },
      child: Text(text),
    );
  }

  Widget buildAdviceCard() {
    if (aiAdviceList.isEmpty) {
      return SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("🤖 AI 맞춤 추천", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          ...aiAdviceList.map((advice) => Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("• ", style: TextStyle(fontSize: 16)),
                Expanded(child: Text(advice, style: TextStyle(fontSize: 14))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget buildTimerCard() {
    bool isRunning = timer?.isActive == true;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text("⏱ 타이머", style: TextStyle(fontSize: 18)),
          if (timerRecommendText.isNotEmpty) ...[
            SizedBox(height: 8),
            GestureDetector(
              onTap: isRunning ? null : () => startTimer(timerRecommendSeconds),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      timerRecommendText,
                      style: TextStyle(fontSize: 13, color: Colors.amberAccent),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 10),
          Text(
            "${(currentTime ~/ 60).toString().padLeft(2, '0')}:${(currentTime % 60).toString().padLeft(2, '0')}",
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          // 진행 바
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: timerProgress,
              minHeight: 12,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                isRunning ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ),
          SizedBox(height: 5),
          if (totalTime > 0)
            Text(
              "${((timerProgress) * 100).toStringAsFixed(0)}% 완료",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: isRunning ? null : () => startTimer(5 * 60),
                child: Text("5분"),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: isRunning ? null : () => startTimer(10 * 60),
                child: Text("10분"),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: isRunning ? null : () => startTimer(25 * 60),
                child: Text("25분"),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => resetTimer(),
                child: Text("초기화"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: Text("안녕 $userName 👋")),

      bottomNavigationBar: _isBannerLoaded && _bannerAd != null
          ? SafeArea(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,

      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [

            // 입력
            slider("수면", sleep, 12, (v){sleep=v;}),
            slider("스트레스", stress, 10, (v){stress=v;}),

            GestureDetector(
              onTap: (){
                setState(() {
                  showDetail = !showDetail;
                });
              },
              child: Text(
                showDetail ? "▲ 상세 입력 닫기" : "▼ 상세 입력 열기",
                style: TextStyle(color: Colors.blue),
              ),
            ),

            if (showDetail) ...[
              slider("공부", study, 12, (v){study=v;}),
              slider("운동", exercise, 5, (v){exercise=v;}),
              slider("앉은시간", sit, 12, (v){sit=v;}),
            ],

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: calculateAI,
              child: Text("AI 분석"),
            ),

            SizedBox(height: 10),

            // 오늘 기록 저장 / 히스토리
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (fatigue == 0 && statusText.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("먼저 AI 분석을 실행해주세요!")),
                      );
                      return;
                    }
                    saveDailyLog();
                  },
                  icon: Icon(Icons.save),
                  label: Text("오늘 기록 저장"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: showDailyLogHistory,
                  icon: Icon(Icons.history),
                  label: Text("기록 보기"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                ),
              ],
            ),

            SizedBox(height: 20),

            // AI 한줄 메시지
            if (aiMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.deepPurple.withValues(alpha: 0.3),
                      Colors.indigo.withValues(alpha: 0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text("🤖 ", style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        aiMessage,
                        style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),

            if (aiMessage.isNotEmpty) SizedBox(height: 20),

            // 오늘의 목표
            buildGoalCard(),

            SizedBox(height: 20),

            // 상태 카드 (글로우 애니메이션)
            AnimatedBuilder(
              animation: Listenable.merge([_glowAnimation, _colorAnimation]),
              builder: (context, child) {
                final animColor = _colorAnimation.value ?? statusColor;
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: animColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: animColor.withValues(alpha: _glowAnimation.value * 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: animColor.withValues(alpha: _glowAnimation.value * 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text("오늘 상태", style: TextStyle(fontSize: 18)),
                      SizedBox(height: 10),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 22, color: animColor, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "피로도 ${fatigue.toStringAsFixed(1)}",
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 20),

            // AI 추천 카드
            buildAdviceCard(),

            SizedBox(height: 20),

            // 타이머 카드 (진행 바 포함)
            buildTimerCard(),

            SizedBox(height: 20),

            // 행동 버튼
            actionButton("스트레칭"),
            actionButton("집중 시작"),

            SizedBox(height: 20),

            Text("📊 최근 피로도"),
            buildChart(),
          ],
        ),
      ),
    );
  }
}
