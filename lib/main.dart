import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
//import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as Math;
import 'package:url_launcher/url_launcher.dart';

const double kCardSize = 100.0; // 画像ノートのサイズ
const double kTextCardWidth = 150.0; // テキストノート用に広げる横幅

/// 利用可能なテクスチャ画像のパス一覧
const List<String> textures = [
  'assets/text_note_washi.png',
  'assets/text_note_texture.png',
  'assets/text_note_fine_paper.png',
  'assets/text_note_craft.png',
  'assets/text_note_woodgrain.png',
];

/// textures[i] に対応する「表示用テクスチャ名」
const List<String> textureNames = ['和紙', 'しわ紙', '高級紙', 'クラフト紙', '木目'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  await Hive.openBox('notes');
  await Hive.openBox('trash');
  await Hive.openBox('settings');
  runApp(const MemoApp());
}

class MemoApp extends StatelessWidget {
  const MemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemoApp',
      theme: ThemeData(primarySwatch: Colors.orange),
      home: const BoardPage(),
    );
  }
}

class Note {
  String id;
  String? text;
  String title;
  String? body;
  File? image;
  Color color;
  bool alwaysOnTop;
  DateTime? dueDate;
  double x;
  double y;
  double scale;
  int zIndex;
  double opacity;
  String texture;

  Note({
    required this.id,
    this.text,
    required this.title,
    this.body,
    this.image,
    required this.color,
    this.alwaysOnTop = false,
    this.dueDate,
    this.x = 20.0,
    this.y = 20.0,
    this.scale = 1.0,
    this.zIndex = 0,
    this.opacity = 1.0,
    this.texture = 'assets/text_note_texture.png',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'imagePath': image?.path,
    'color': color.toARGB32(),
    'alwaysOnTop': alwaysOnTop,
    'dueDate': dueDate?.toIso8601String(),
    'x': x,
    'y': y,
    'scale': scale,
    'zIndex': zIndex,
    'opacity': opacity,
    'texture': texture,
  };

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'] ?? '',
      body: json['body'],
      image: json['imagePath'] != null ? File(json['imagePath']) : null,
      color: Color(json['color']),
      alwaysOnTop: json['alwaysOnTop'] ?? false,
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      x: (json['x'] ?? 20.0).toDouble(),
      y: (json['y'] ?? 20.0).toDouble(),
      scale: (json['scale'] ?? 1.0).toDouble(),
      zIndex: json['zIndex'] ?? 0,
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      texture: json['texture'] ?? 'assets/text_note_texture.png',
    );
  }
}

class BoardPage extends StatefulWidget {
  const BoardPage({Key? key}) : super(key: key);

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  final List<Note> notes = [];
  final box = Hive.box('notes');
  final picker = ImagePicker();
  int _zCounter = 0;
  final Map<String, Offset> _basePositions = {};
  bool hasShownPinchHint = false;

  /// 各ノートのピンチ開始時の scale を保持するマップ
  final Map<String, double> _baseScales = {};

  @override
  void initState() {
    super.initState();
    // Hive から読み込み
    for (var m in box.values.cast<Map>()) {
      notes.add(Note.fromJson(Map<String, dynamic>.from(m)));
    }
    hasShownPinchHint = Hive.box(
      'settings',
    ).get('shownPinchHint', defaultValue: false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void saveNotes() {
    box.clear();
    for (var note in notes) {
      box.add(note.toJson());
    }
  }

  // ── 長押しで編集モーダル ──
  // ── _showEditModal の新しい定義 ──
  void _showEditModal(Note note) {
    final titleController = TextEditingController(text: note.title);
    final bodyController = TextEditingController(text: note.body ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // 一時変数
        String tempTitle = note.title;
        String tempBody = note.body ?? '';
        File? tempImage = note.image;
        Color tempColor = note.color;
        bool tempOnTop = note.alwaysOnTop;
        String tempTexture = note.texture;
        int selectedTex = textures.indexOf(tempTexture);
        if (selectedTex < 0) selectedTex = 0;

        return StatefulBuilder(
          builder: (context, setModalState) {
            // カラーチョイス
            final colorChoices = <Color>[
              Colors.yellow,
              Colors.green,
              Colors.pink,
              Colors.blue,
              Colors.orange,
              Colors.grey,
            ];
            if (!colorChoices.contains(tempColor)) {
              colorChoices.insert(0, tempColor);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ★ここから if–else で排他にする★
                  if (note.image == null) ...[
                    // ◎ テキストノート用：タイトルと本文
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // タイトル入力欄（右端に余白つき）
                        Expanded(
                          child: TextFormField(
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: 'タイトル',
                              contentPadding: EdgeInsets.only(right: 48),
                            ),
                          ),
                        ),
                        // ゴミ箱ボタン（アイコン）
                        IconButton(
                          tooltip: 'ゴミ箱へ移動',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            // ここに「ゴミ箱へ移動」処理を書く
                            final trashBox = Hive.box('trash');
                            setState(() {
                              trashBox.add(note.toJson());
                              notes.remove(note);
                              saveNotes();
                            });
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    TextFormField(
                      controller: bodyController,
                      decoration: const InputDecoration(labelText: '本文（任意）'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    // ■ 画像ノート用 UI
                    if (tempImage != null)
                      SizedBox(
                        height: 160, // ここ大きめ
                        child: Stack(
                          children: [
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  tempImage!,
                                  width: 128, // 大きめ
                                  height: 128,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                tooltip: 'ゴミ箱へ移動',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  final trashBox = Hive.box('trash');
                                  setState(() {
                                    trashBox.add(note.toJson());
                                    notes.remove(note);
                                    saveNotes();
                                  });
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    // ボタン2つをRowで横並び
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.crop),
                          label: const Text('切り取り'),
                          onPressed:
                              tempImage == null
                                  ? null // 画像がなければ無効
                                  : () async {
                                    final cropped = await ImageCropper()
                                        .cropImage(
                                          sourcePath: tempImage!.path,
                                          aspectRatio: const CropAspectRatio(
                                            ratioX: 1,
                                            ratioY: 1,
                                          ),
                                        );
                                    if (cropped != null) {
                                      setModalState(() {
                                        tempImage = File(cropped.path);
                                      });
                                    }
                                  },
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.photo_library),
                          label: const Text('画像を選び直す'),
                          onPressed: () async {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                            );
                            if (picked == null) return;
                            setModalState(() {
                              tempImage = File(picked.path);
                            });
                          },
                        ),
                      ],
                    ),
                  ],

                  // ★ここまで if–else ★

                  // ■ テクスチャ選択（テキストノートのときだけ表示）
                  if (note.image == null)
                    Row(
                      children: [
                        const Text('テクスチャ：'),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: tempTexture,
                          items:
                              textures.map((path) {
                                final idx = textures.indexOf(path);
                                return DropdownMenuItem(
                                  value: path,
                                  child: Row(
                                    children: [
                                      Image.asset(
                                        path,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.cover,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(textureNames[idx]),
                                    ],
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              (t) => setModalState(() => tempTexture = t!),
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  // ■ 前面トグル ＋ 枠色選択
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // スイッチ
                      const Text('常に前面'),
                      const SizedBox(width: 8),
                      Switch(
                        value: tempOnTop,
                        onChanged: (v) => setModalState(() => tempOnTop = v),
                      ),

                      const SizedBox(width: 24), // スイッチと枠色の間隔
                      // 枠色 Dropdown（オンのときだけ選択可能）
                      Opacity(
                        opacity: tempOnTop ? 1.0 : 0.5,
                        child: Row(
                          children: [
                            const Text('枠色：'),
                            const SizedBox(width: 8),
                            DropdownButton<Color>(
                              value: tempColor,
                              items:
                                  colorChoices.map((c) {
                                    return DropdownMenuItem<Color>(
                                      value: c,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        color: c,
                                      ),
                                    );
                                  }).toList(),
                              onChanged:
                                  tempOnTop
                                      ? (c) =>
                                          setModalState(() => tempColor = c!)
                                      : null,
                              underline: const SizedBox(),
                              isDense: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 更新ボタン ──
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (note.image == null) {
                          // テキストノートならタイトル／本文／テクスチャを更新
                          note.title = titleController.text;
                          note.body =
                              bodyController.text.isNotEmpty
                                  ? bodyController.text
                                  : null;
                          note.texture = tempTexture;
                        } else {
                          // 画像ノートなら画像だけを更新
                          note.image = tempImage;
                        }

                        // 共通項目：枠色・前面トグル・zIndex
                        note.color = tempColor;
                        note.alwaysOnTop = tempOnTop;
                        note.zIndex = ++_zCounter;
                      });

                      // Hive に保存
                      saveNotes();
                      // モーダルを閉じる
                      Navigator.pop(context);
                    },
                    child: const Text('更新'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── テキスト付箋追加 ──
  Future<void> addTextNote() async {
    String tempTitle = '';
    String tempBody = '';
    String tempTexture = textures[0];
    int selectedTex = 0;
    Color selected = Colors.yellow;
    bool onTop = false;

    final titleController = TextEditingController(text: tempTitle);
    final bodyController = TextEditingController(text: tempBody);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // タイトル入力
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'タイトル',
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 本文入力
                    TextField(
                      controller: bodyController,
                      decoration: const InputDecoration(
                        hintText: '本文（任意）',
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    // テクスチャ選択
                    Row(
                      children: [
                        const Text('テクスチャ：'),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: tempTexture,
                          items:
                              textures.map((path) {
                                final idx = textures.indexOf(path);
                                return DropdownMenuItem(
                                  value: path,
                                  child: Row(
                                    children: [
                                      Image.asset(
                                        path,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.cover,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(textureNames[idx]),
                                    ],
                                  ),
                                );
                              }).toList(),
                          onChanged:
                              (t) => setModalState(() => tempTexture = t!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 前面スイッチ＋枠色
                    Row(
                      children: [
                        const Text('常に前面'),
                        const SizedBox(width: 8),
                        Switch(
                          value: onTop,
                          onChanged: (v) => setModalState(() => onTop = v),
                        ),
                        const SizedBox(width: 24),
                        const Text('枠色：'),
                        const SizedBox(width: 8),
                        Opacity(
                          opacity: onTop ? 1.0 : 0.5,
                          child: DropdownButton<Color>(
                            value: selected,
                            items:
                                [
                                      Colors.yellow,
                                      Colors.green,
                                      Colors.pink,
                                      Colors.blue,
                                      Colors.orange,
                                      Colors.grey,
                                    ]
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          color: c,
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                onTop
                                    ? (c) => setModalState(() => selected = c!)
                                    : null,
                            isDense: true,
                            underline: const SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        onPressed: () {
                          // 1. コントローラーから最新値を取得
                          final latestTitle = titleController.text;
                          final latestBody = bodyController.text;

                          // 2. Noteを追加（追加ボタン用の場合。編集の場合は編集処理！）
                          setState(() {
                            notes.add(
                              Note(
                                id: DateTime.now().toIso8601String(),
                                title: latestTitle,
                                body: latestBody.isNotEmpty ? latestBody : null,
                                texture: tempTexture,
                                color: selected,
                                alwaysOnTop: onTop,
                                zIndex: ++_zCounter,
                              ),
                            );
                            saveNotes();
                          });

                          // 3. モーダルを閉じる
                          Navigator.pop(context);
                        },
                        child: const Text('完了'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // 入力があればリストに追加
    if (tempTitle.trim().isNotEmpty) {
      setState(() {
        notes.add(
          Note(
            id: DateTime.now().toIso8601String(),
            title: tempTitle,
            body: tempBody.isNotEmpty ? tempBody : null,
            texture: tempTexture,
            color: selected,
            alwaysOnTop: onTop,
            zIndex: ++_zCounter,
          ),
        );
        saveNotes();
      });
      // ★ ここから追加！初回のみピンチヒントダイアログ表示 ★
      if (!hasShownPinchHint) {
        hasShownPinchHint = true;
        box.put('shownPinchHint', true); // Hiveなどに保存
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text('ヒント'),
                content: Text('ノートは2本指でピンチ操作すると、拡大・縮小できます！'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('OK'),
                  ),
                ],
              ),
        );
      }
    }
  }

  // ── 画像付箋追加 ──
  Future<void> addImageNote() async {
    File? finalImage;
    if (Platform.isWindows) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.single.path == null) return;
      finalImage = File(result.files.single.path!);
    } else {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      finalImage = File(picked.path);
    }

    Color selected = Colors.yellow;
    bool onTop = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        // ここで一時変数を初期化
        File? tempImage = finalImage;
        Color tempColor = selected;
        bool tempOnTop = onTop;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // プレビュー
                  if (tempImage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            tempImage!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  // 画像を選びなおす
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 切り取りボタン
                      ElevatedButton.icon(
                        icon: const Icon(Icons.crop),
                        label: const Text('切り取り'),
                        onPressed:
                            tempImage == null
                                ? null
                                : () async {
                                  final cropped = await ImageCropper()
                                      .cropImage(
                                        sourcePath: tempImage!.path,
                                        aspectRatio: const CropAspectRatio(
                                          ratioX: 1,
                                          ratioY: 1,
                                        ),
                                      );
                                  if (cropped == null) return;
                                  setModalState(() {
                                    tempImage = File(cropped.path);
                                  });
                                },
                      ),
                      const SizedBox(width: 16),
                      // 画像を選びなおすボタン
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('画像を選びなおす'),
                        onPressed: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked == null) return;
                          setModalState(() {
                            tempImage = File(picked.path);
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('常に前面'),
                      const SizedBox(width: 8),
                      Switch(
                        value: tempOnTop,
                        onChanged: (v) => setModalState(() => tempOnTop = v),
                      ),
                      const SizedBox(width: 24),
                      Opacity(
                        opacity: tempOnTop ? 1.0 : 0.5,
                        child: Row(
                          children: [
                            const Text('枠色：'),
                            const SizedBox(width: 8),
                            DropdownButton<Color>(
                              value: tempColor,
                              items:
                                  [
                                        Colors.yellow,
                                        Colors.green,
                                        Colors.pink,
                                        Colors.blue,
                                        Colors.orange,
                                        Colors.grey,
                                      ]
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            color: c,
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  tempOnTop
                                      ? (c) =>
                                          setModalState(() => tempColor = c!)
                                      : null,
                              underline: const SizedBox(),
                              isDense: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        // 【重要！】モーダル外の変数に値をコピー
                        finalImage = tempImage;
                        selected = tempColor;
                        onTop = tempOnTop;
                        Navigator.pop(c);
                      },
                      child: const Text('完了'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );

    if (finalImage != null) {
      setState(() {
        notes.add(
          Note(
            id: DateTime.now().toIso8601String(),
            title: '',
            body: null,
            image: finalImage,
            color: selected,
            alwaysOnTop: onTop,
            zIndex: ++_zCounter,
          ),
        );
        saveNotes();
      });
      // ★ここから追加！初回のみピンチヒントダイアログ表示
      if (!hasShownPinchHint) {
        hasShownPinchHint = true;
        Hive.box('settings').put('shownPinchHint', true);
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text('ヒント'),
                content: Text('ノートは2本指でピンチ操作すると、拡大・縮小できます！'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('OK'),
                  ),
                ],
              ),
        );
      }
    }
  }

  void _centerAllNotes() {
    final size = MediaQuery.of(context).size;
    final count = notes.length;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    setState(() {
      for (int i = 0; i < count; i++) {
        final note = notes[i];
        final noteWidth =
            note.image != null
                ? kCardSize * note.scale
                : kTextCardWidth * note.scale;
        final noteHeight =
            note.image != null
                ? kCardSize * note.scale
                : 100.0 * note.scale; // テキストノート仮高さ

        // --- 渦巻き状のずらし量を計算 ---
        // 半径（広がり具合、必要に応じて調整）
        double radius = 24.0 + 16.0 * i; // 2枚目以降ほど外側へ
        double angle = i * 0.6; // 0.6ラジアンずつ回転、調整可能

        // 円運動
        double offsetX = radius * Math.cos(angle);
        double offsetY = radius * Math.sin(angle);

        // ノートの中心が中央＋オフセットになるように配置
        note.x = centerX - noteWidth / 2 + offsetX;
        note.y = centerY - noteHeight / 2 + offsetY;
      }
      saveNotes();
    });
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. ノートを中央に集める
              ElevatedButton.icon(
                icon: Icon(Icons.center_focus_strong),
                label: Text('ノートを中央に集める'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder:
                        (ctx2) => AlertDialog(
                          title: Text('確認'),
                          content: Text('すべてのノートを中央に移動します。よろしいですか？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx2).pop(false),
                              child: Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx2).pop(true),
                              child: Text('OK'),
                            ),
                          ],
                        ),
                  );

                  if (confirmed == true) {
                    _centerAllNotes();
                    Navigator.pop(ctx); // モーダルを閉じる
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('ノートを中央に集めました')));
                  }
                },
              ),
              SizedBox(height: 20),

              // 2. 背景画像の変更
              ElevatedButton.icon(
                icon: Icon(Icons.wallpaper),
                label: Text('背景画像を変更'),
                onPressed: () {
                  // 機能は後回し。今は閉じるだけ
                  Navigator.pop(ctx);
                },
              ),
              SizedBox(height: 20),

              // 3. 全ノート削除
              ElevatedButton.icon(
                icon: Icon(Icons.delete_forever),
                label: Text('全ノートを削除'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // 機能は後回し。今は閉じるだけ
                  Navigator.pop(ctx);
                },
              ),
              SizedBox(height: 32),

              // 4. アプリ情報
              Text(
                'アプリ情報',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('MemoApp v1.0.0'),
              Text('開発者：あなたの名前'),
              Text('お問い合わせ：example@email.com'),
              // プライバシーポリシーリンクなどはここに追加OK
            ],
          ),
        );
      },
    );
  }

  void _openTrashSheet() {
    final trashBox = Hive.box('trash');
    // Hive から現在のゴミ箱リストを作成（新しい順に逆順にする！）
    List<Note> trashNotes =
        trashBox.values
            .cast<Map>()
            .map((m) => Note.fromJson(Map<String, dynamic>.from(m)))
            .toList()
            .reversed
            .toList(); // ← 追加ポイント

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 16,
                  left: 16,
                  right: 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Column(
                    children: [
                      Expanded(
                        child:
                            trashNotes.isEmpty
                                ? const Center(child: Text('ゴミ箱は空です'))
                                : ListView.builder(
                                  itemCount: trashNotes.length,
                                  itemBuilder: (_, i) {
                                    final note = trashNotes[i];
                                    return ListTile(
                                      leading:
                                          note.image != null
                                              ? Image.file(
                                                note.image!,
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                              )
                                              : Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: note.color.withAlpha(
                                                    180,
                                                  ),
                                                  image: DecorationImage(
                                                    image: AssetImage(
                                                      note.texture,
                                                    ),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  note.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                      title: Text(
                                        note.title.isNotEmpty
                                            ? note.title
                                            : '画像ノート',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // ── 復元ボタン ──
                                          IconButton(
                                            icon: const Icon(
                                              Icons.restore,
                                              color: Colors.green,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                notes.add(note);
                                                saveNotes();
                                                trashNotes.removeAt(i);
                                                trashBox.deleteAt(
                                                  trashBox.length - 1 - i,
                                                ); // ←逆順にしたのでindex変わる
                                              });
                                              setModalState(() {});
                                            },
                                          ),
                                          // ── 完全削除ボタン ──
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_forever,
                                              color: Colors.red,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                trashNotes.removeAt(i);
                                                trashBox.deleteAt(
                                                  trashBox.length - 1 - i,
                                                ); // ←逆順にしたのでindex変わる
                                              });
                                              setModalState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                      ),
                      // ↓↓↓ 追加：一番下に「ゴミ箱を空にする」ボタン ↓↓↓
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(Icons.delete_forever),
                          label: Text('ゴミ箱を空にする'),
                          onPressed:
                              trashNotes.isEmpty
                                  ? null
                                  : () async {
                                    final confirm = await showDialog(
                                      context: context,
                                      builder:
                                          (ctx) => AlertDialog(
                                            title: Text('確認'),
                                            content: Text('本当にゴミ箱を空にしますか？'),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      ctx,
                                                      false,
                                                    ),
                                                child: Text('キャンセル'),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      ctx,
                                                      true,
                                                    ),
                                                child: Text('空にする'),
                                              ),
                                            ],
                                          ),
                                    );
                                    if (confirm == true) {
                                      await trashBox.clear();
                                      setModalState(() {
                                        trashNotes.clear();
                                      });
                                    }
                                  },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  void _showResizeModal(Note note) {
    double tempScale = note.scale;
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setStateModal) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('サイズ調整', style: TextStyle(fontSize: 16)),
                      Slider(
                        min: 0.5,
                        max: 3.0,
                        divisions: 15,
                        label: '${(tempScale * 100).round()}%',
                        value: tempScale,
                        onChanged: (v) => setStateModal(() => tempScale = v),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            note.scale = tempScale;
                            saveNotes();
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('適用'),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showPreviewModal(Note note) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              // ↓↓↓ ここでノートのタイプごとに異なるサイズに分岐 ↓↓↓
              child:
                  note.image != null
                      // 画像ノート（大きく＆ピンチ拡大）
                      ? SizedBox(
                        width: MediaQuery.of(context).size.width * 0.96,
                        height: MediaQuery.of(context).size.height * 0.75,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(
                              color:
                                  note.alwaysOnTop
                                      ? note.color
                                      : Colors.transparent,
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, offset: Offset(2, 2)),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 5.0,
                              child: Image.file(
                                note.image!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      )
                      // テキストノート（元のサイズで）
                      : SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.width * 0.9 * 1.414,
                        child: Container(
                          decoration: BoxDecoration(
                            color: note.color.withAlpha((0.8 * 255).round()),
                            image: DecorationImage(
                              image: AssetImage(note.texture),
                              fit: BoxFit.cover,
                            ),
                            border: Border.all(
                              color:
                                  note.alwaysOnTop
                                      ? note.color
                                      : Colors.transparent,
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, offset: Offset(2, 2)),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SelectableText(
                                note.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              if (note.body != null &&
                                  note.body!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: SelectableText(
                                      note.body!,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.black87,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<Note>.from(notes)..sort((a, b) {
      // 1. alwaysOnTop=true の方が上
      if (a.alwaysOnTop != b.alwaysOnTop) {
        return a.alwaysOnTop ? -1 : 1;
      }
      // 2. zIndexが大きい方が上
      return b.zIndex.compareTo(a.zIndex);
    });

    print('--- sorted notes ---');
    for (var note in sorted) {
      print(
        'title: ${note.title}, alwaysOnTop: ${note.alwaysOnTop}, zIndex: ${note.zIndex}',
      );
    }
    print('---------------------');

    return Scaffold(
      endDrawer: Drawer(
        child: ListView(
          children: [
            Container(
              color: Colors.orange[200],
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ), // 余白調整
              alignment: Alignment.centerLeft,
              child: Text(
                '設定',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(Icons.center_focus_strong),
              title: Text('ノートを中央に集める'),
              onTap: () async {
                Navigator.pop(context); // Drawer閉じる
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: Text('確認'),
                        content: Text('すべてのノートを中央に移動します。よろしいですか？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text('OK'),
                          ),
                        ],
                      ),
                );
                if (confirmed == true) {
                  _centerAllNotes();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('ノートを中央に集めました')));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('ゴミ箱を開く'),
              onTap: () {
                Navigator.pop(context);
                _openTrashSheet();
              },
            ),
            //ListTile(
            //  leading: Icon(Icons.wallpaper),
            //  title: Text('背景画像を変更'),
            //  onTap: () {
            //    Navigator.pop(context);
            //    // ここに背景画像切替処理
            //  },
            //),
            ListTile(
              leading: Icon(Icons.delete_forever),
              title: Text('すべてのノートをゴミ箱に移動'),
              onTap: () async {
                Navigator.pop(context); // Drawer閉じる

                // 確認ダイアログ
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: Text('確認'),
                        content: Text(
                          'すべてのノートをゴミ箱に移動します。よろしいですか？\nこの操作は取り消せません。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(
                              '移動する',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                );

                if (confirmed == true) {
                  final trashBox = Hive.box('trash');
                  setState(() {
                    for (var note in notes) {
                      trashBox.add(note.toJson());
                    }
                    notes.clear();
                    saveNotes();
                  });

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('すべてのノートをゴミ箱に移動しました')));
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('アプリ情報'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: 'MemoApp',
                  applicationVersion: 'v1.0.0',
                  applicationLegalese: '© 2024 あなたの名前',
                  children: [Text('お問い合わせ：example@email.com')],
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.mail_outline),
              title: Text('お問い合わせ'),
              onTap: () async {
                String tempMessage = '';
                await showDialog(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: Text('お問い合わせ'),
                        content: TextField(
                          autofocus: true,
                          maxLines: 5,
                          onChanged: (v) => tempMessage = v,
                          decoration: InputDecoration(
                            hintText: 'ご質問・ご要望などを入力してください',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () async {
                              // 入力が空なら何もしない
                              if (tempMessage.trim().isEmpty) {
                                Navigator.of(ctx).pop();
                                return;
                              }
                              final email =
                                  'your_email@example.com'; // ←あなたのアドレス
                              final subject = Uri.encodeComponent(
                                'MemoApp お問い合わせ',
                              );
                              final body = Uri.encodeComponent(tempMessage);
                              final uri = Uri.parse(
                                'mailto:$email?subject=$subject&body=$body',
                              );
                              final success = await launchUrl(uri);
                              print('launchUrl: $success');

                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                              Navigator.of(ctx).pop();
                            },
                            child: Text('送信'),
                          ),
                        ],
                      ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.privacy_tip),
              title: Text('プライバシーポリシー'),
              onTap: () {
                Navigator.pop(context);
                // ここに規約リンク表示など
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/cork_board.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            for (var note in sorted.reversed) ...[
              Positioned(
                key: ValueKey(note.id),
                left: note.x,
                top: note.y,
                child: Transform.scale(
                  scale: note.scale,
                  alignment: Alignment.topLeft,
                  transformHitTests: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showPreviewModal(note),
                    onLongPress: () => _showEditModal(note),
                    onScaleStart: (details) {
                      _baseScales[note.id] = note.scale;
                      setState(() {
                        note.zIndex = ++_zCounter;
                      });
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        final base = _baseScales[note.id] ?? 1.0;
                        note.scale = (base * details.scale).clamp(0.5, 3.0);
                        note.x += details.focalPointDelta.dx;
                        note.y += details.focalPointDelta.dy;
                      });
                    },
                    onScaleEnd: (_) {
                      setState(() {
                        note.zIndex = ++_zCounter; // ここでzIndexを更新！
                        print('ノート移動: ${note.title}, zIndex=${note.zIndex}');
                        saveNotes();
                      });
                    },
                    // ここを書き換え ↓↓↓
                    child:
                        note.image != null
                            // ■ 画像ノートは正方形
                            ? SizedBox(
                              width: kCardSize,
                              height: kCardSize,
                              child: NoteCard(note: note),
                            )
                            // ■ テキストノートは幅だけ固定、高さは NoteCard の中身に任せる
                            : SizedBox(
                              width: kTextCardWidth,
                              child: NoteCard(note: note),
                            ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 歯車ボタンを「右サイドメニューを開く」に変更
          Builder(
            builder:
                (context) => FloatingActionButton(
                  heroTag: 'settingsBtn',
                  onPressed: () {
                    Scaffold.of(context).openEndDrawer();
                  },
                  tooltip: '設定',
                  child: Icon(Icons.settings),
                ),
          ),
          SizedBox(height: 12),
          // ── 追加ボタン ──
          FloatingActionButton(
            heroTag: 'addBtn',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder:
                    (c) => SizedBox(
                      height: 160,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.text_fields),
                            title: const Text('テキスト付箋'),
                            onTap: () {
                              Navigator.pop(c);
                              addTextNote();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.image),
                            title: const Text('画像付箋'),
                            onTap: () {
                              Navigator.pop(c);
                              addImageNote();
                            },
                          ),
                        ],
                      ),
                    ),
              );
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

const bool kShowPinIcon = false;

class NoteCard extends StatelessWidget {
  final Note note;
  const NoteCard({Key? key, required this.note}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── 画像なら余白なし、テキストなら余白あり ──
        Container(
          width: note.image != null ? kCardSize : kTextCardWidth,
          padding:
              note.image != null ? EdgeInsets.zero : const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // 画像ノートは透明背景、テキストノートはカラー＋テクスチャ
            color:
                note.image != null
                    ? Colors.transparent
                    : note.color.withAlpha((0.8 * 255).round()),
            image:
                note.image == null
                    ? DecorationImage(
                      image: AssetImage(note.texture),
                      fit: BoxFit.cover,
                    )
                    : null,
            border: Border.all(
              color: note.alwaysOnTop ? note.color : Colors.transparent,
              width: 1.0,
            ),
            boxShadow: const [BoxShadow(blurRadius: 4, offset: Offset(2, 2))],
          ),
          child:
              note.image != null
                  ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Opacity(
                      // ここで画像そのものを透過
                      opacity: note.opacity,
                      child: Image.file(
                        note.image!,
                        width: kCardSize,
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                  : Center(
                    child: Text(
                      note.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
        ),
        if (kShowPinIcon && note.alwaysOnTop)
          Positioned(
            top: -4,
            right: -4,
            child: Icon(
              Icons.push_pin,
              size: 20,
              color: Colors.redAccent.withAlpha((0.9 * 255).round()),
            ),
          ),
      ],
    );
  }
}
