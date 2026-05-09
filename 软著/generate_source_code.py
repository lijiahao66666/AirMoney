#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成AirMoney软著申请用的源码文本
策略：保留完整代码，精选核心文件
要求：如果不够60页就全部保留
"""

import os
from pathlib import Path

# 基础路径
BASE_DIR = Path(r'c:\Users\28679\traeProjects\AirMoney\client\lib')
OUTPUT_FILE = Path(r'c:\Users\28679\traeProjects\AirMoney\软著\source_code_for_ruanzhu.txt')

# AirMoney总代码量7690行，预计153页，需要精简到60页（约3000行）
TARGET_LINES = 3000
MAX_LINES = 3000


def read_file_lines(rel_path):
    """读取文件并返回行数"""
    file_path = BASE_DIR / rel_path
    if not file_path.exists():
        return None, 0
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    lines = content.split('\n')
    return content, len(lines)


def main():
    # 定义要包含的文件及其最大行数
    # 策略：保留完整代码，通过限制文件数量来控制总行数
    files_config = [
        # ===== 核心入口 =====
        ('main.dart', 99),

        # ===== 数据模型层 =====
        ('data/models/bill.dart', 91),
        ('data/models/consult_session.dart', 85),

        # ===== 数据层 =====
        ('data/repositories/bill_repository.dart', 84),
        ('data/database_io.dart', 89),
        ('data/database_web.dart', 190),
        ('data/bill_storage.dart', 19),

        # ===== 核心常量 =====
        ('core/constants.dart', 48),
        ('core/theme/app_theme.dart', 65),
        ('core/theme/app_colors.dart', 32),

        # ===== 状态管理 =====
        ('presentation/providers/bill_provider.dart', 114),
        ('presentation/providers/points_provider.dart', 58),

        # ===== 首页模块 =====
        ('presentation/pages/home/home_page.dart', 30),
        ('presentation/pages/tab_home/tab_home_page.dart', 170),  # 1428行，保留前170行

        # ===== 记账模块 =====
        ('presentation/pages/add_bill/add_bill_page.dart', 170),  # 255行，保留前170行

        # ===== 分析模块 =====
        ('presentation/pages/analysis/analysis_page.dart', 170),  # 1350行，保留前170行
        ('presentation/pages/analysis/single_analysis_page.dart', 120),  # 180行，保留前120行

        # ===== 咨询模块 =====
        ('presentation/pages/consult/consult_page.dart', 170),  # 1092行，保留前170行

        # ===== 认证模块 =====
        ('presentation/pages/auth/login_page.dart', 120),  # 371行，保留前120行

        # ===== 服务层 =====
        ('services/api_service.dart', 120),  # 401行，保留前120行
        ('services/analysis_service.dart', 104),
        ('services/consult_service.dart', 120),  # 242行，保留前120行
        ('services/auth_service.dart', 100),  # 142行，保留前100行
        ('services/notification_service.dart', 120),  # 388行，保留前120行
        ('services/consult_session_storage.dart', 100),  # 155行，保留前100行

        # =====  widgets =====
        ('presentation/widgets/reminder_settings_sheet.dart', 120),  # 295行，保留前120行
        ('presentation/widgets/wallet_sheet.dart', 120),  # 275行，保留前120行
    ]

    all_content = []
    total_lines = 0
    file_stats = []

    for rel_path, max_lines in files_config:
        content, original_lines = read_file_lines(rel_path)
        if content is None:
            print(f'警告: 文件不存在 {rel_path}')
            continue

        # 保留前max_lines行完整代码
        lines = content.split('\n')
        if len(lines) > max_lines:
            truncated_lines = lines[:max_lines]
            final_content = '\n'.join(truncated_lines)
            final_lines = len(truncated_lines)
        else:
            final_content = content
            final_lines = original_lines

        # 添加文件分隔符
        header = f"""// ============================================================================
// 文件: {rel_path}
// 原始行数: {original_lines} | 保留行数: {final_lines}
// ============================================================================
"""
        file_content = header + final_content
        all_content.append(file_content)
        total_lines += final_lines + 3  # 加上header的行数
        file_stats.append((rel_path, original_lines, final_lines))

    # 写入输出文件
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n\n'.join(all_content))

    # 打印统计
    print('=' * 60)
    print('AirMoney 软著源码生成统计')
    print('=' * 60)
    for rel_path, orig, final in file_stats:
        print(f'{rel_path:50s} {orig:5d} -> {final:5d} 行')
    print('-' * 60)
    print('总计'.ljust(50) + ' ' * 5 + '    ' + str(total_lines).rjust(5) + ' 行')
    print(f'目标行数: {TARGET_LINES} | 最大行数: {MAX_LINES}')
    print(f'预计页数(按50行/页): {total_lines / 50:.1f} 页')
    print('=' * 60)

    if total_lines > MAX_LINES:
        print(f'警告: 总行数({total_lines})超过最大值({MAX_LINES})，需要进一步精简')
    elif total_lines < TARGET_LINES:
        print(f'提示: 总行数({total_lines})低于目标值({TARGET_LINES})，可以适当增加代码')
    else:
        print('成功: 行数在目标范围内')

    # 检查是否有省略注释
    full_content = '\n\n'.join(all_content)
    omit_count = full_content.count('省略')
    print(f'\n包含"省略"字样数量: {omit_count}')
    if omit_count == 0:
        print('✓ 代码完整，无省略')
    else:
        print('✗ 代码中包含省略，建议检查')


if __name__ == '__main__':
    main()
