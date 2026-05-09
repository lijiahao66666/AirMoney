#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成AirMoney软著申请用的源码PDF
要求：前30页+后30页，共60页，每页不少于50行
如果不足60页则全部提交
"""

from pathlib import Path
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.lib.colors import black, gray

# 尝试注册中文字体
chinese_font = None
font_paths = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\simsun.ttc',
]

for fp in font_paths:
    try:
        name = Path(fp).stem
        pdfmetrics.registerFont(TTFont(name, fp))
        chinese_font = name
        print(f'成功注册字体: {name} ({fp})')
        break
    except Exception as e:
        print(f'注册字体失败 {fp}: {e}')
        continue

if not chinese_font:
    print('警告: 未找到中文字体，将使用默认字体')
    chinese_font = 'Helvetica'

# 文件路径
INPUT_FILE = Path(r'c:\Users\28679\traeProjects\AirMoney\软著\source_code_for_ruanzhu.txt')
OUTPUT_FILE = Path(r'c:\Users\28679\traeProjects\AirMoney\软著\AirMoney_源码.pdf')

# 页面设置
PAGE_WIDTH, PAGE_HEIGHT = A4
MARGIN_LEFT = 20 * mm
MARGIN_RIGHT = 20 * mm
MARGIN_TOP = 25 * mm
MARGIN_BOTTOM = 20 * mm
CONTENT_WIDTH = PAGE_WIDTH - MARGIN_LEFT - MARGIN_RIGHT

# 代码字体设置
CODE_FONT_SIZE = 8
CODE_LINE_HEIGHT = 10  # 每行高度
LINES_PER_PAGE = 50    # 每页固定50行


def draw_page(c, page_lines, page_num, total_pages):
    """绘制一页内容"""
    # 页眉
    c.setFont(chinese_font, 9)
    c.setFillColor(gray)
    header_text = f'哎呀钱 AirMoney - 源程序鉴别材料'
    c.drawCentredString(PAGE_WIDTH / 2, PAGE_HEIGHT - 15, header_text)

    # 绘制代码行
    c.setFont('Courier', CODE_FONT_SIZE)
    c.setFillColor(black)

    y = PAGE_HEIGHT - MARGIN_TOP
    for line in page_lines:
        # 处理中文字体显示
        has_chinese = any('\u4e00' <= ch <= '\u9fff' for ch in line)
        if has_chinese:
            c.setFont(chinese_font, CODE_FONT_SIZE)
        else:
            c.setFont('Courier', CODE_FONT_SIZE)

        # 截断过长的行
        max_chars = int(CONTENT_WIDTH / (CODE_FONT_SIZE * 0.6))
        display_line = line[:max_chars]

        c.drawString(MARGIN_LEFT, y, display_line)
        y -= CODE_LINE_HEIGHT

    # 页脚
    c.setFont(chinese_font, 9)
    c.setFillColor(gray)
    footer_text = f'- {page_num} -'
    c.drawCentredString(PAGE_WIDTH / 2, MARGIN_BOTTOM - 10, footer_text)


def main():
    # 读取源码
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    total_lines = len(lines)
    print(f'源码总行数: {total_lines}')

    # 计算页数
    total_pages = (total_lines + LINES_PER_PAGE - 1) // LINES_PER_PAGE
    print(f'总页数: {total_pages}')

    if total_pages > 60:
        print(f'警告: 页数({total_pages})超过60页，需要精简源码')
        # 只取前30页和后30页
        front_lines = lines[:30 * LINES_PER_PAGE]
        back_lines = lines[-30 * LINES_PER_PAGE:]
        lines = front_lines + ['\n// ... 中间部分代码省略 ...\n'] + back_lines
        total_lines = len(lines)
        total_pages = (total_lines + LINES_PER_PAGE - 1) // LINES_PER_PAGE
        print(f'截取后页数: {total_pages}')
    else:
        print(f'提示: 页数({total_pages})不足60页，全部提交')

    # 创建PDF
    c = Canvas(str(OUTPUT_FILE), pagesize=A4)

    for page_num in range(1, total_pages + 1):
        start_idx = (page_num - 1) * LINES_PER_PAGE
        end_idx = min(start_idx + LINES_PER_PAGE, total_lines)
        page_lines = lines[start_idx:end_idx]

        # 如果最后一页不足50行，用空行补齐（确保每页至少50行）
        while len(page_lines) < LINES_PER_PAGE:
            page_lines.append('')

        draw_page(c, page_lines, page_num, total_pages)
        c.showPage()

    c.save()

    import os
    file_size = os.path.getsize(OUTPUT_FILE) / 1024
    print(f'PDF生成成功: {OUTPUT_FILE}')
    print(f'总页数: {total_pages}')
    print(f'文件大小: {file_size:.1f} KB')


if __name__ == '__main__':
    main()
