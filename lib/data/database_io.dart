import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'bill_storage.dart';
import 'models/bill.dart';

BillStorage createBillStorage() => _SqfliteBillStorage();

class _SqfliteBillStorage implements BillStorage {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final dbPath = join(dir, 'airmoney.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            pay_method TEXT,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_bills_date ON bills(date)');
      },
    );
    return _db!;
  }

  @override
  Future<int> insert(Bill bill) async {
    final db = await _database;
    return db.insert('bills', bill.toMap());
  }

  @override
  Future<List<Map<String, dynamic>>> query({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await _database;
    return db.query(
      'bills',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    final db = await _database;
    return db.rawQuery(sql, args);
  }
}
