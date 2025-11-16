// main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';


void main() {

  WidgetsFlutterBinding.ensureInitialized();
  runApp(

    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        ChangeNotifierProxyProvider<AuthProvider, TaskProvider>(
          create: (_) => TaskProvider(null),
          update: (_, auth, previousTasks) => TaskProvider(auth.currentUser),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'ToDo List',
      theme: ThemeData(
        primarySwatch: themeProvider.themeColor,
        brightness: Brightness.light,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: themeProvider.themeColor,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}


class UserModel {
  final int id;
  final String nomPrenom;
  final String email;

  UserModel({required this.id, required this.nomPrenom, required this.email});

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      nomPrenom: map['nom_prenom'],
      email: map['email'],
    );
  }
}

class TaskModel {
  int? id;
  final int userId;
  String titre;
  String contenu;
  bool estComplete;

  TaskModel({
    this.id,
    required this.userId,
    required this.titre,
    required this.contenu,
    this.estComplete = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'titre': titre,
      'contenu': contenu,
      'estComplete': estComplete ? 1 : 0,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'],
      userId: map['userId'],
      titre: map['titre'],
      contenu: map['contenu'],
      estComplete: map['estComplete'] == 1,
    );
  }
}



class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, 'todo_app.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom_prenom TEXT,
        email TEXT UNIQUE,
        password TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        titre TEXT,
        contenu TEXT,
        estComplete INTEGER DEFAULT 0,
        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE preferences(
        userId INTEGER PRIMARY KEY,
        couleur INTEGER,
        image_fond TEXT,
        theme_mode TEXT,
        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<UserModel?> registerUser(String nom, String email, String password) async {
    final db = await database;
    try {
      int id = await db.insert('users', {'nom_prenom': nom, 'email': email, 'password': password},
          conflictAlgorithm: ConflictAlgorithm.fail);
      return UserModel(id: id, nomPrenom: nom, email: email);
    } catch (e) {
      debugPrint("Erreur d'inscription: $e");
      return null;
    }
  }

  Future<UserModel?> loginUser(String email, String password) async {
    final db = await database;
    var res = await db.query('users', where: 'email = ? AND password = ?', whereArgs: [email, password]);
    return res.isNotEmpty ? UserModel.fromMap(res.first) : null;
  }

  Future<int> addTask(TaskModel task) async {
    final db = await database;
    return await db.insert('tasks', task.toMap());
  }

  Future<List<TaskModel>> getTasks(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('tasks', where: 'userId = ?', whereArgs: [userId]);
    return List.generate(maps.length, (i) => TaskModel.fromMap(maps[i]));
  }

  Future<int> updateTask(TaskModel task) async {
    final db = await database;
    return await db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveThemePreferences(int userId, Color color, String? imagePath, String themeMode) async {
    final db = await database;
    await db.insert(
      'preferences',
      {'userId': userId, 'couleur': color.value, 'image_fond': imagePath, 'theme_mode': themeMode},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getThemePreferences(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('preferences', where: 'userId = ?', whereArgs: [userId]);
    return maps.isNotEmpty ? maps.first : null;
  }
}


class AuthProvider with ChangeNotifier {
  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<bool> login(String email, String password) async {
    _currentUser = await DatabaseHelper().loginUser(email, password);
    if (_currentUser != null) {
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> register(String name, String email, String password) async {
    _currentUser = await DatabaseHelper().registerUser(name, email, password);
    if (_currentUser != null) {
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}

class ThemeProvider with ChangeNotifier {
  MaterialColor _themeColor = Colors.pink;
  String? _backgroundImagePath;
  ThemeMode _themeMode = ThemeMode.system;

  MaterialColor get themeColor => _themeColor;
  String? get backgroundImagePath => _backgroundImagePath;
  ThemeMode get themeMode => _themeMode;

  Future<void> loadPreferences(UserModel user) async {
    var prefs = await DatabaseHelper().getThemePreferences(user.id);
    if (prefs != null) {
      _themeColor = _getMaterialColor(Color(prefs['couleur'] ?? Colors.pink.value));
      _backgroundImagePath = (prefs['image_fond'] as String?)?.isNotEmpty == true ? prefs['image_fond'] : null;
      switch (prefs['theme_mode']) {
        case 'light': _themeMode = ThemeMode.light; break;
        case 'dark': _themeMode = ThemeMode.dark; break;
        default: _themeMode = ThemeMode.system;
      }
    } else {
      _themeColor = Colors.pink;
      _backgroundImagePath = null;
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> updateTheme({MaterialColor? newColor, String? newBgImage, ThemeMode? newMode, required UserModel user}) async {
    _themeColor = newColor ?? _themeColor;
    _backgroundImagePath = (newBgImage?.isNotEmpty ?? false) ? newBgImage : null;
    _themeMode = newMode ?? _themeMode;

    await DatabaseHelper().saveThemePreferences(user.id, _themeColor, _backgroundImagePath, _themeMode.name);
    notifyListeners();
  }

  MaterialColor _getMaterialColor(Color color) {
    final int red = color.red;
    final int green = color.green;
    final int blue = color.blue;
    final Map<int, Color> shades = {
      50: Color.fromRGBO(red, green, blue, .1), 100: Color.fromRGBO(red, green, blue, .2),
      200: Color.fromRGBO(red, green, blue, .3), 300: Color.fromRGBO(red, green, blue, .4),
      400: Color.fromRGBO(red, green, blue, .5), 500: Color.fromRGBO(red, green, blue, .6),
      600: Color.fromRGBO(red, green, blue, .7), 700: Color.fromRGBO(red, green, blue, .8),
      800: Color.fromRGBO(red, green, blue, .9), 900: Color.fromRGBO(red, green, blue, 1),
    };
    return MaterialColor(color.value, shades);
  }
}

class TaskProvider with ChangeNotifier {
  final UserModel? _currentUser;
  List<TaskModel> _tasks = [];

  TaskProvider(this._currentUser) {
    if (_currentUser != null) {
      fetchTasks();
    }
  }

  List<TaskModel> get tasks => _tasks;

  Future<void> fetchTasks() async {
    if (_currentUser != null) {
      _tasks = await DatabaseHelper().getTasks(_currentUser!.id);
      notifyListeners();
    }
  }

  Future<void> addTask(String titre, String contenu) async {
    if (_currentUser != null) {
      TaskModel newTask = TaskModel(userId: _currentUser!.id, titre: titre, contenu: contenu);
      await DatabaseHelper().addTask(newTask);
      await fetchTasks();
    }
  }

  Future<void> updateTask(TaskModel task) async {
    await DatabaseHelper().updateTask(task);
    await fetchTasks();
  }

  Future<void> deleteTask(int id) async {
    await DatabaseHelper().deleteTask(id);
    await fetchTasks();
  }

  Future<void> toggleTaskStatus(TaskModel task) async {
    task.estComplete = !task.estComplete;
    await updateTask(task);
  }
}


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(_emailController.text.trim(), _passwordController.text.trim());

    if (success && mounted) {
      await context.read<ThemeProvider>().loadPreferences(authProvider.currentUser!);
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(user: authProvider.currentUser!)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email ou mot de passe incorrect"), backgroundColor: Colors.red),
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<ThemeProvider>().themeColor;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 80, color: themeColor),
                const SizedBox(height: 20),
                Text('ToDo List', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: themeColor)),
                const SizedBox(height: 50),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Adresse mail', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => (value?.isEmpty ?? true) ? "Veuillez entrer un email" : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)),
                  obscureText: true,
                  validator: (value) => (value?.isEmpty ?? true) ? "Veuillez entrer un mot de passe" : null,
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  CircularProgressIndicator(color: themeColor)
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _login,
                      child: const Text("Se connecter", style: TextStyle(fontSize: 18)),
                    ),
                  ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: Text("Pas de compte ? S'inscrire", style: TextStyle(color: themeColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//--- Écran d'Inscription ---
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  void _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (success && mounted) {
      await context.read<ThemeProvider>().loadPreferences(authProvider.currentUser!);
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(user: authProvider.currentUser!)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cet email est déjà utilisé"), backgroundColor: Colors.red),
      );
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<ThemeProvider>().themeColor;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Créer un compte', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: themeColor)),
                const SizedBox(height: 50),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nom & Prénoms', prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) => (value?.isEmpty ?? true) ? "Veuillez entrer votre nom" : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Adresse mail', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => (value?.isEmpty ?? true) ? "Veuillez entrer un email" : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)),
                  obscureText: true,
                  validator: (value) =>
                  (value?.length ?? 0) < 6 ? "Le mot de passe doit faire au moins 6 caractères" : null,
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  CircularProgressIndicator(color: themeColor)
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _register,
                      child: const Text("S'inscrire", style: TextStyle(fontSize: 18)),
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

//--- Écran d'Accueil ---
class HomeScreen extends StatelessWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  void _showTaskDialog(BuildContext context, {TaskModel? task}) {
    final titreController = TextEditingController(text: task?.titre);
    final contenuController = TextEditingController(text: task?.contenu);
    final taskProvider = context.read<TaskProvider>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(task == null ? 'Nouvelle Tâche' : 'Modifier la Tâche'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titreController, decoration: const InputDecoration(labelText: 'Titre')),
              const SizedBox(height: 8),
              TextField(controller: contenuController, decoration: const InputDecoration(labelText: 'Contenu')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                final titre = titreController.text;
                final contenu = contenuController.text;
                if (titre.isNotEmpty) {
                  if (task == null) {
                    taskProvider.addTask(titre, contenu);
                  } else {
                    task.titre = titre;
                    task.contenu = contenu;
                    taskProvider.updateTask(task);
                  }
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Sauvegarder'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final taskProvider = context.watch<TaskProvider>();

    return Scaffold(
      body: Container(
        decoration: themeProvider.backgroundImagePath != null
            ? BoxDecoration(
          image: DecorationImage(
            image: FileImage(File(themeProvider.backgroundImagePath!)),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken),
          ),
        )
            : null,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text('Bonjour, ${user.nomPrenom}'),
              floating: true,
              pinned: true,
              snap: false,
              backgroundColor: themeProvider.backgroundImagePath != null ? Colors.transparent : null,
              elevation: 0,
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'preferences') {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PreferencesScreen(user: user)));
                    } else if (value == 'deconnexion') {
                      context.read<AuthProvider>().logout();
                      Navigator.of(context)
                          .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(value: 'preferences', child: Text('Préférences')),
                    const PopupMenuItem<String>(value: 'deconnexion', child: Text('Déconnexion')),
                  ],
                ),
              ],
            ),
            if (taskProvider.tasks.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    "Vous n'avez aucune tâche.",
                    style: TextStyle(fontSize: 18, color: themeProvider.themeMode == ThemeMode.dark || themeProvider.backgroundImagePath != null ? Colors.white70 : Colors.black54),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final task = taskProvider.tasks[index];
                    return Card(
                      elevation: 4.0,
                      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                      color: task.estComplete
                          ? (themeProvider.themeMode == ThemeMode.dark ? Colors.white.withOpacity(0.1) : Colors.grey.shade300)
                          : Theme.of(context).cardColor.withOpacity(0.9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                        leading: Checkbox(
                          value: task.estComplete,
                          onChanged: (_) => taskProvider.toggleTaskStatus(task),
                          activeColor: themeProvider.themeColor,
                        ),
                        title: Text(task.titre,
                            style: TextStyle(
                                decoration: task.estComplete ? TextDecoration.lineThrough : TextDecoration.none,
                                fontWeight: FontWeight.bold,
                                color: task.estComplete ? Colors.grey[500] : null)),
                        subtitle: Text(task.contenu),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Confirmation'),
                                content: const Text('Voulez-vous vraiment supprimer cette tâche ?'),
                                actions: [
                                  TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(ctx).pop()),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('Supprimer'),
                                    onPressed: () {
                                      taskProvider.deleteTask(task.id!);
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        onTap: () => _showTaskDialog(context, task: task),
                      ),
                    );
                  },
                  childCount: taskProvider.tasks.length,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class PreferencesScreen extends StatelessWidget {
  final UserModel user;
  const PreferencesScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final ImagePicker picker = ImagePicker();

    return Scaffold(
      appBar: AppBar(title: const Text('Préférences')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Mode d\'affichage', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Clair'), icon: Icon(Icons.wb_sunny)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Sombre'), icon: Icon(Icons.nightlight_round)),
              ButtonSegment(value: ThemeMode.system, label: Text('Système'), icon: Icon(Icons.computer)),
            ],
            selected: {themeProvider.themeMode},
            onSelectionChanged: (newSelection) {
              context.read<ThemeProvider>().updateTheme(newMode: newSelection.first, user: user);
            },
          ),
          const Divider(height: 40),
          Text('Arrière-plan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Choisir une image de fond'),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                context.read<ThemeProvider>().updateTheme(newBgImage: image.path, user: user);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.hide_image),
            title: const Text("Supprimer l'image de fond"),
            // Passe une chaîne vide pour indiquer la suppression
            onTap: () => context.read<ThemeProvider>().updateTheme(newBgImage: '', user: user),
          ),
        ],
      ),
    );
  }
}