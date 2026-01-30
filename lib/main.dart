import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:bcrypt/bcrypt.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.instance.init();
  runApp(const App());
}

// ======================= ДАННЫЕ АДМИНА =======================
const adminLogin = "lllv3d@yandex.ru";
const adminPassword = "qwe123qwe";

// ======================= DB LAYER =======================
class LocalDb {
  LocalDb._();
  static final instance = LocalDb._();

  late Database _db;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, "app_local.db");

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            login TEXT UNIQUE NOT NULL,
            pass_hash TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE photos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_login TEXT NOT NULL,
            file_path TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<bool> userExists(String login) async {
    final rows = await _db.query(
      "users",
      where: "lower(login)=lower(?)",
      whereArgs: [login],
    );
    return rows.isNotEmpty;
  }

  Future<void> registerUser(String login, String password) async {
    final hash = BCrypt.hashpw(password, BCrypt.gensalt());
    await _db.insert("users", {"login": login, "pass_hash": hash});
  }

  Future<bool> checkUser(String login, String password) async {
    final rows = await _db.query(
      "users",
      where: "lower(login)=lower(?)",
      whereArgs: [login],
    );
    if (rows.isEmpty) return false;

    final hash = rows.first["pass_hash"] as String;
    return BCrypt.checkpw(password, hash);
  }

  Future<List<PhotoItem>> getPhotos({
    required bool admin,
    required String currentLogin,
  }) async {
    List<Map<String, Object?>> rows;
    if (admin) {
      rows = await _db.query("photos", orderBy: "created_at DESC");
    } else {
      rows = await _db.query(
        "photos",
        where: "owner_login=?",
        whereArgs: [currentLogin],
        orderBy: "created_at DESC",
      );
    }

    return rows
        .map(
          (r) => PhotoItem(
            id: r["id"] as int,
            ownerLogin: r["owner_login"] as String,
            filePath: r["file_path"] as String,
            createdAt: r["created_at"] as int,
          ),
        )
        .toList();
  }

  Future<int> insertPhoto({
    required String ownerLogin,
    required String filePath,
  }) async {
    return await _db.insert("photos", {
      "owner_login": ownerLogin,
      "file_path": filePath,
      "created_at": DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deletePhoto(int photoId) async {
    final rows = await _db.query(
      "photos",
      where: "id=?",
      whereArgs: [photoId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final path = rows.first["file_path"] as String;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    await _db.delete("photos", where: "id=?", whereArgs: [photoId]);
  }
}

class PhotoItem {
  final int id;
  final String ownerLogin;
  final String filePath;
  final int createdAt;

  PhotoItem({
    required this.id,
    required this.ownerLogin,
    required this.filePath,
    required this.createdAt,
  });
}

// ======================= AUTH SESSION =======================
class Session {
  final String login;
  final bool isAdmin;
  Session(this.login, this.isAdmin);
}

// ======================= APP =======================
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Фото-система",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: const LoginScreen(),
    );
  }
}

// ======================= UI: LOGIN =======================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    loginCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> doLogin() async {
    final login = loginCtrl.text.trim();
    final pass = passCtrl.text.trim();

    if (login.isEmpty || pass.isEmpty) {
      _snack("Введи логин и пароль");
      return;
    }

    setState(() => loading = true);

    try {
      // admin
      if (login.toLowerCase() == adminLogin.toLowerCase() &&
          pass == adminPassword) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GalleryScreen(session: Session(adminLogin, true)),
          ),
        );
        return;
      }

      // user
      final ok = await LocalDb.instance.checkUser(login, pass);
      if (!ok) {
        _snack("Неверный логин или пароль");
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GalleryScreen(session: Session(login, false)),
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Авторизация",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: loginCtrl,
                      decoration: const InputDecoration(
                        labelText: "логин",
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      decoration: const InputDecoration(
                        labelText: "пароль",
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => doLogin(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : doLogin,
                        child: loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(),
                              )
                            : const Text("Войти"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                        loginCtrl.clear();
                        passCtrl.clear();
                      },
                      child: const Text("как зарегистрироваться"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= UI: REGISTER =======================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final pass2Ctrl = TextEditingController();

  bool okShown = false;
  bool loading = false;

  @override
  void dispose() {
    loginCtrl.dispose();
    passCtrl.dispose();
    pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> doRegister() async {
    final login = loginCtrl.text.trim();
    final pass = passCtrl.text.trim();
    final pass2 = pass2Ctrl.text.trim();

    if (login.isEmpty || pass.isEmpty || pass2.isEmpty) {
      _snack("Заполни все поля");
      return;
    }
    if (login.toLowerCase() == adminLogin.toLowerCase()) {
      _snack("Этот логин зарезервирован (администратор)");
      return;
    }
    if (pass != pass2) {
      _snack("Пароли не совпадают");
      return;
    }

    setState(() => loading = true);
    try {
      final exists = await LocalDb.instance.userExists(login);
      if (exists) {
        _snack("Пользователь уже существует");
        return;
      }

      await LocalDb.instance.registerUser(login, pass);

      setState(() => okShown = true);

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Регистрация")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: loginCtrl,
                      decoration: const InputDecoration(
                        labelText: "логин",
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      decoration: const InputDecoration(
                        labelText: "пароль",
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pass2Ctrl,
                      decoration: const InputDecoration(
                        labelText: "подтверждение пароля",
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => doRegister(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading ? null : doRegister,
                        child: loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(),
                              )
                            : const Text("Зарегистрироваться"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (okShown)
                      const Text(
                        "Регистрация прошла успешно",
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w800),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= UI: GALLERY =======================
class GalleryScreen extends StatefulWidget {
  final Session session;
  const GalleryScreen({super.key, required this.session});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final picker = ImagePicker();
  List<PhotoItem> photos = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final list = await LocalDb.instance.getPhotos(
      admin: widget.session.isAdmin,
      currentLogin: widget.session.login,
    );
    if (!mounted) return;
    setState(() {
      photos = list;
      loading = false;
    });
  }

  Future<String> _saveImageToAppDir(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = p.extension(source.path);
    final name = "img_${DateTime.now().millisecondsSinceEpoch}_${_uuid()}$ext";
    final path = p.join(dir.path, name);
    await source.copy(path);
    return path;
  }

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> addPhoto() async {
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    final savedPath = await _saveImageToAppDir(File(x.path));
    await LocalDb.instance.insertPhoto(
      ownerLogin: widget.session.login,
      filePath: savedPath,
    );
    await _refresh();
  }

  Future<void> deletePhoto(PhotoItem item) async {
    if (!widget.session.isAdmin) return;
    await LocalDb.instance.deletePhoto(item.id);
    await _refresh();
  }

  Future<void> showDeleteModal(PhotoItem item) async {
    if (!widget.session.isAdmin) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Удалить фотографию?",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text("Это действие нельзя отменить."),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Отмена"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("Удалить"),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );

    if (ok == true) {
      await deletePhoto(item);
    }
  }

  Future<void> logout() async {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.session.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? "Галерея (Админ)" : "Галерея"),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addPhoto,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : photos.isEmpty
              ? const Center(child: Text("Пока нет фотографий"))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (_, i) {
                    final item = photos[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullscreenPhotoScreen(
                              filePath: item.filePath,
                              ownerLogin: item.ownerLogin,
                            ),
                          ),
                        );
                      },
                      onLongPress: isAdmin ? () => showDeleteModal(item) : null,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(item.filePath),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                item.ownerLogin,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (isAdmin)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.white),
                                onPressed: () => showDeleteModal(item),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withOpacity(0.4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ======================= FULLSCREEN VIEW =======================
class FullscreenPhotoScreen extends StatelessWidget {
  final String filePath;
  final String ownerLogin;

  const FullscreenPhotoScreen({
    super.key,
    required this.filePath,
    required this.ownerLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(filePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.35),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  ownerLogin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
