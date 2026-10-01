import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static bool _ffiInitialized = false;

  /// On desktop (Windows/Linux/macOS) the default sqflite plugin has no native
  /// implementation, so we route through the FFI factory backed by the bundled
  /// SQLite library. Android and iOS keep the standard plugin.
  static void _ensureDesktopFactory() {
    if (_ffiInitialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _ensureDesktopFactory();
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'buildify.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE projects ADD COLUMN branch TEXT DEFAULT \'main\'');
      await db.execute('ALTER TABLE projects ADD COLUMN build_command TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN publish_dir TEXT');
      await db.execute('ALTER TABLE projects ADD COLUMN base_dir TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        hosting_mode TEXT NOT NULL,
        source_uri TEXT NOT NULL,
        local_path TEXT NOT NULL,
        port INTEGER NOT NULL,
        subdomain TEXT,
        env_vars TEXT,
        branch TEXT DEFAULT 'main',
        build_command TEXT,
        publish_dir TEXT,
        base_dir TEXT,
        desired_state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_active_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE deployments (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        commit_hash TEXT,
        status TEXT NOT NULL,
        log_file_path TEXT,
        started_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
  }

  // Project CRUD operations
  Future<int> insertProject(Map<String, dynamic> project) async {
    final db = await database;
    return await db.insert('projects', project, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getProjects() async {
    final db = await database;
    return await db.query('projects', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getProject(String id) async {
    final db = await database;
    final results = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<int> updateProject(String id, Map<String, dynamic> updates) async {
    final db = await database;
    return await db.update('projects', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProject(String id) async {
    final db = await database;
    return await db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // Deployment CRUD operations
  Future<int> insertDeployment(Map<String, dynamic> deployment) async {
    final db = await database;
    return await db.insert('deployments', deployment, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getDeployments(String projectId) async {
    final db = await database;
    return await db.query(
      'deployments',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'started_at DESC',
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('deployments');
    await db.delete('projects');
  }
}
