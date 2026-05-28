import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/bluetooth_peer.dart';

class DatabaseHelper {
  static const _databaseName = "bluechat.db";
  static const _databaseVersion = 4;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<String> getDatabasePath() async {
    return join(await getDatabasesPath(), _databaseName);
  }

  Future<void> closeDb() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> initDb() async {
    _database = await _initDatabase();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migrate sessions table
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN wallpaper TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN members TEXT");
      } catch (_) {}

      // Migrate peers table
      try {
        await db.execute("ALTER TABLE peers ADD COLUMN custom_name TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE peers ADD COLUMN profile_photo TEXT");
      } catch (_) {}

      // Migrate messages table
      try {
        await db.execute("ALTER TABLE messages ADD COLUMN reply_to_id TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE messages ADD COLUMN reply_to_body TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE messages ADD COLUMN reply_to_sender TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE messages ADD COLUMN reaction TEXT");
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN is_pinned INTEGER DEFAULT 0");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN is_muted INTEGER DEFAULT 0");
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute("ALTER TABLE peers ADD COLUMN connection_status TEXT DEFAULT 'none'");
      } catch (_) {}
    }
  }

  Future _onCreate(Database db, int version) async {
    // Create sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_group INTEGER NOT NULL,
        last_message TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        wallpaper TEXT,
        members TEXT,
        is_pinned INTEGER DEFAULT 0,
        is_muted INTEGER DEFAULT 0
      )
    ''');

    // Create messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        sender_address TEXT NOT NULL,
        body TEXT NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT,
        file_name TEXT,
        file_size INTEGER,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        is_self INTEGER NOT NULL,
        reply_to_id TEXT,
        reply_to_body TEXT,
        reply_to_sender TEXT,
        reaction TEXT,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');

    // Create peers table
    await db.execute('''
      CREATE TABLE peers (
        address TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        bonded INTEGER NOT NULL,
        color TEXT,
        initials TEXT,
        shared_key TEXT,
        custom_name TEXT,
        profile_photo TEXT,
        connection_status TEXT DEFAULT 'none'
      )
    ''');
  }

  // --- Session Operations ---
  Future<int> insertSession(ChatSession session) async {
    Database db = await instance.database;
    return await db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatSession>> getSessions() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('sessions', orderBy: 'timestamp DESC');
    
    List<ChatSession> sessions = [];
    for (var map in maps) {
      final sessionId = map['id'] as String;
      final unread = await getUnreadCount(sessionId);
      sessions.add(ChatSession.fromMap(map, unreadCount: unread));
    }
    return sessions;
  }

  Future<int> getUnreadCount(String sessionId) async {
    Database db = await instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM messages WHERE session_id = ? AND is_self = 0 AND status != 'read'",
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markSessionRead(String sessionId) async {
    Database db = await instance.database;
    await db.update(
      'messages',
      {'status': 'read'},
      where: 'session_id = ? AND is_self = 0 AND status != \'read\'',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateSessionLastMessage(String sessionId, String text, int timestamp) async {
    Database db = await instance.database;
    return await db.update(
      'sessions',
      {
        'last_message': text,
        'timestamp': timestamp,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateSessionName(String sessionId, String name) async {
    Database db = await instance.database;
    return await db.update(
      'sessions',
      {'name': name},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateSessionPin(String sessionId, bool isPinned) async {
    Database db = await instance.database;
    return await db.update(
      'sessions',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateSessionMute(String sessionId, bool isMuted) async {
    Database db = await instance.database;
    return await db.update(
      'sessions',
      {'is_muted': isMuted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> deleteSession(String sessionId) async {
    Database db = await instance.database;
    // Messages will be deleted automatically due to cascade, but just in case:
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    return await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // --- Message Operations ---
  Future<int> insertMessage(ChatMessage message) async {
    Database db = await instance.database;
    return await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => ChatMessage.fromMap(maps[i]));
  }

  Future<int> updateMessageStatus(String messageId, String status) async {
    Database db = await instance.database;
    return await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> updateMessageBodyAndType(String messageId, String body, String type) async {
    Database db = await instance.database;
    return await db.update(
      'messages',
      {
        'body': body,
        'type': type,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> updateMessageFilePath(String messageId, String filePath) async {
    Database db = await instance.database;
    return await db.update(
      'messages',
      {'file_path': filePath},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<int> deleteMessage(String messageId) async {
    Database db = await instance.database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<int> clearChatHistory(String sessionId) async {
    Database db = await instance.database;
    await db.update(
      'sessions',
      {'last_message': 'No messages', 'timestamp': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  // --- Peer Operations ---
  Future<int> insertOrUpdatePeer(BluetoothPeer peer) async {
    Database db = await instance.database;
    return await db.insert(
      'peers',
      peer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BluetoothPeer>> getPeers() async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('peers');
    return List.generate(maps.length, (i) => BluetoothPeer.fromMap(maps[i]));
  }

  Future<BluetoothPeer?> getPeer(String address) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'peers',
      where: 'address = ?',
      whereArgs: [address],
    );
    if (maps.isNotEmpty) {
      return BluetoothPeer.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updatePeerSharedKey(String address, String? sharedKey) async {
    Database db = await instance.database;
    return await db.update(
      'peers',
      {'shared_key': sharedKey},
      where: 'address = ?',
      whereArgs: [address],
    );
  }

  Future<int> updatePeerCustomName(String address, String? customName) async {
    Database db = await instance.database;
    return await db.update(
      'peers',
      {'custom_name': customName},
      where: 'address = ?',
      whereArgs: [address],
    );
  }

  Future<int> updatePeerConnectionStatus(String address, String status) async {
    Database db = await instance.database;
    return await db.update(
      'peers',
      {'connection_status': status},
      where: 'address = ?',
      whereArgs: [address],
    );
  }

  Future<int> updatePeerProfilePhoto(String address, String? profilePhotoPath) async {
    Database db = await instance.database;
    return await db.update(
      'peers',
      {'profile_photo': profilePhotoPath},
      where: 'address = ?',
      whereArgs: [address],
    );
  }

  Future<int> updateSessionWallpaper(String sessionId, String? wallpaperPath) async {
    Database db = await instance.database;
    return await db.update(
      'sessions',
      {'wallpaper': wallpaperPath},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<int> updateMessageReaction(String messageId, String? reaction) async {
    Database db = await instance.database;
    return await db.update(
      'messages',
      {'reaction': reaction},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}
