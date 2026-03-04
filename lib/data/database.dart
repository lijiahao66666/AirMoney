// 根据平台选择实现：移动/桌面用 sqflite，Web 用 SharedPreferences
import 'bill_storage.dart';

import 'database_web.dart' if (dart.library.io) 'database_io.dart' as db_impl;

BillStorage createBillStorage() => db_impl.createBillStorage();
