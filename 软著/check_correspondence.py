#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查AirMoney说明书功能与源码的对应关系
"""

from pathlib import Path
import re

# 源码文件列表
source_files = [
    'main.dart',
    'data/models/bill.dart',
    'data/models/consult_session.dart',
    'data/repositories/bill_repository.dart',
    'data/database_io.dart',
    'data/database_web.dart',
    'data/bill_storage.dart',
    'core/constants.dart',
    'core/theme/app_theme.dart',
    'core/theme/app_colors.dart',
    'presentation/providers/bill_provider.dart',
    'presentation/providers/points_provider.dart',
    'presentation/pages/home/home_page.dart',
    'presentation/pages/tab_home/tab_home_page.dart',
    'presentation/pages/add_bill/add_bill_page.dart',
    'presentation/pages/analysis/analysis_page.dart',
    'presentation/pages/analysis/single_analysis_page.dart',
    'presentation/pages/consult/consult_page.dart',
    'presentation/pages/auth/login_page.dart',
    'services/api_service.dart',
    'services/analysis_service.dart',
    'services/consult_service.dart',
    'services/auth_service.dart',
    'services/notification_service.dart',
    'services/consult_session_storage.dart',
    'presentation/widgets/reminder_settings_sheet.dart',
    'presentation/widgets/wallet_sheet.dart',
]

# 说明书功能列表及对应关键词
manual_features = {
    '书架管理': ['importBooks', 'deleteBook', 'pinSelectedBooks', 'BookImporter', 'BookParser', 'DatabaseHelper', 'bookshelf', '书架', '导入书籍', 'GridView'],
    '记账功能': ['Bill', 'addBill', 'deleteBill', 'updateBill', 'BillProvider', 'BillRepository', '记账', '支出', '收入', '金额', '分类'],
    '首页展示': ['HomePage', 'TabHomePage', 'SummaryCard', '今日', '本周', '最近记录', '快捷入口'],
    '智能分析': ['AnalysisPage', 'SingleAnalysisPage', 'AnalysisService', 'analyzeSingleBill', 'analyzePeriod', '单次分析', '周期分析', '消费分析'],
    '买前咨询': ['ConsultPage', 'ConsultService', 'ConsultSession', 'consultStream', '买前咨询', '购买意图', '对话'],
    '通知提醒': ['NotificationService', 'flutter_local_notifications', '提醒', '通知', '定时'],
    '用户认证': ['AuthService', 'LoginPage', '短信登录', 'Token', '认证', '登录'],
    '积分管理': ['PointsProvider', 'WalletSheet', '积分', '签到', 'points', 'balance'],
    '数据库': ['SQLite', 'sqflite', 'bills', 'settings', 'insert', 'getAllBills', 'database', 'Repository'],
    '数据模型': ['Bill', 'ConsultSession', 'BillType', 'class Bill'],
    'API服务': ['ApiService', 'chatCompletions', 'HTTP', 'SSE', '流式', '代理'],
}

# 读取所有源码内容
source_content = {}
base_dir = Path(r'c:\Users\28679\traeProjects\AirMoney\软著\source_code_for_ruanzhu.txt')
content = base_dir.read_text(encoding='utf-8')

# 按文件分割
file_blocks = re.split(r'// =+\n// 文件: ', content)
for f in file_blocks[1:]:  # 跳过第一个空块
    lines = f.split('\n')
    filename = lines[0].strip()
    file_content = '\n'.join(lines[1:])
    source_content[filename] = file_content

print('=' * 80)
print('AirMoney 说明书功能 vs 源码对应关系检查')
print('=' * 80)

missing_features = []

for feature, keywords in manual_features.items():
    found = False
    found_files = []
    for filename, file_content in source_content.items():
        for keyword in keywords:
            if keyword in file_content:
                found = True
                if filename not in found_files:
                    found_files.append(filename)
    
    status = '✓ 已对应' if found else '✗ 未找到'
    print('\n' + feature + ' ' + status)
    if found_files:
        for f in found_files:
            print('  -> ' + f)
    else:
        print('  -> 警告: 未找到对应源码文件')
        missing_features.append(feature)

print('\n' + '=' * 80)
print('源码文件覆盖检查')
print('=' * 80)

# 检查每个源码文件是否对应说明书功能
for filename in source_files:
    matched_features = []
    for feature, keywords in manual_features.items():
        for keyword in keywords:
            if filename in source_content and keyword in source_content[filename]:
                if feature not in matched_features:
                    matched_features.append(feature)
    
    if matched_features:
        features_str = ', '.join(matched_features)
        print(filename.ljust(55) + ' -> ' + features_str)
    else:
        print(filename.ljust(55) + ' -> (通用代码/入口)')

print('\n' + '=' * 80)
print('检查总结')
print('=' * 80)
if missing_features:
    print('警告: 以下功能在源码中未找到明确对应:')
    for f in missing_features:
        print('  - ' + f)
else:
    print('✓ 所有说明书功能在源码中均有对应')

print('\n源码文件总数: ' + str(len(source_content)))
print('说明书功能模块数: ' + str(len(manual_features)))
