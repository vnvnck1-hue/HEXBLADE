"""Render the project-local storyboard specification as a Korean review PDF."""
from pathlib import Path
import html
import json
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer,
    Table, TableStyle,
)
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
SOURCE = ROOT / '맘모스_죽음연출_기능명세서.md'
OUTPUT = PROJECT / 'output' / 'pdf' / '맘모스_죽음연출_콘티와_기능명세서.pdf'
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('Korean', 'C:/Windows/Fonts/malgun.ttf'))
pdfmetrics.registerFont(TTFont('KoreanBold', 'C:/Windows/Fonts/malgunbd.ttf'))
pdfmetrics.registerFontFamily('Korean', normal='Korean', bold='KoreanBold',
                            italic='Korean', boldItalic='KoreanBold')

NAVY = colors.HexColor('#162335')
CYAN = colors.HexColor('#028699')
MUTED = colors.HexColor('#607083')
PALE = colors.HexColor('#F2F6FA')
PAGE_W, PAGE_H = landscape(A4)
MARGIN_X = 42
CONTENT_W = PAGE_W - 2 * MARGIN_X

body = ParagraphStyle('Body', fontName='Korean', fontSize=9.5, leading=15,
                      textColor=NAVY, wordWrap='CJK', spaceAfter=8)
h1 = ParagraphStyle('Title', parent=body, fontName='KoreanBold', fontSize=24,
                    leading=34, spaceAfter=20, keepWithNext=True)
h2 = ParagraphStyle('Heading', parent=body, fontName='KoreanBold', fontSize=14,
                    leading=21, textColor=CYAN, spaceBefore=12, spaceAfter=9,
                    keepWithNext=True)
cell = ParagraphStyle('Cell', parent=body, fontSize=8.4, leading=12.4,
                      spaceAfter=0)
head_cell = ParagraphStyle('HeadCell', parent=cell, fontName='KoreanBold',
                           textColor=colors.white, fontSize=8.6, leading=12.6)
code = ParagraphStyle('Code', parent=body, fontSize=8.8, leading=13.5,
                      backColor=PALE, borderPadding=10, spaceAfter=12)
bullet = ParagraphStyle('Bullet', parent=body, leftIndent=14, firstLineIndent=-11)


def markup(text):
    text = html.escape(text, quote=True)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)',
                  lambda m: f'<link href="{m[2]}" color="#028699">{m[1]}</link>', text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'`([^`]+)`', r'<font color="#475B73">\1</font>', text)
    return text


def table_widths(header):
    count = len(header)
    if count == 5:
        if header[0] == '안':
            weights = [18, 25, 9, 23, 25]
        elif header[0] == '포즈':
            weights = [18, 22, 28, 10, 22]
        else:
            weights = [14, 13, 25, 34, 14]
    elif count == 4:
        weights = [27, 15, 15, 43]
    elif count == 3:
        weights = [25, 36, 39]
        if header[0] in ('파일', '필드'):
            weights = [31, 28, 41]
    elif count == 2:
        weights = [35, 65]
    else:
        weights = [100 / count] * count
    return [CONTENT_W * weight / 100 for weight in weights]


def make_table(lines):
    rows = [[s.strip() for s in line.strip().strip('|').split('|')] for line in lines]
    header = rows[0]
    rows = [row for row in rows if not all(re.fullmatch(r':?-{3,}:?', c) for c in row)]
    rendered = []
    for idx, row in enumerate(rows):
        if len(row) != len(header):
            raise ValueError(f'Incorrect table column count: {row}')
        rendered.append([Paragraph(markup(c), head_cell if idx == 0 else cell) for c in row])
    result = Table(rendered, colWidths=table_widths(header), repeatRows=1,
                   hAlign='LEFT', spaceBefore=4, spaceAfter=13)
    result.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), NAVY),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, PALE]),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 9),
        ('RIGHTPADDING', (0, 0), (-1, -1), 9),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LINEBELOW', (0, 0), (-1, 0), 1, CYAN),
        ('LINEBELOW', (0, 1), (-1, -1), 0.25, colors.HexColor('#DAE3EB')),
    ]))
    return result


story = []
lines = SOURCE.read_text(encoding='utf-8').splitlines()
i = 0
while i < len(lines):
    line = lines[i].strip()
    if not line:
        i += 1
        continue
    if line.startswith('# '):
        story.append(Paragraph(markup(line[2:]), h1))
        story.append(Paragraph('2026년 9월 30일  ·  Godot Neon Arena Claude  ·  기획과 구현 요구사항',
                               ParagraphStyle('Meta', parent=body, textColor=MUTED, fontSize=9)))
    elif line.startswith('## '):
        if line.startswith('## 18 '):
            closing = [Paragraph(markup(line[3:]), h2)]
            for text_line in lines[i + 1:]:
                if text_line.strip():
                    closing.append(Paragraph(markup(text_line.strip()), body))
            story.append(KeepTogether(closing))
            break
        if line.startswith(('## 7 ', '## 12 ', '## 17 ')):
            story.append(PageBreak())
        story.append(Paragraph(markup(line[3:]), h2))
    elif line.startswith('!['):
        match = re.fullmatch(r'!\[([^\]]+)\]\(([^)]+)\)', line)
        if not match:
            raise ValueError(f'Incorrect image line: {line}')
        # Each six-panel board gets a dedicated landscape page at native aspect.
        heading = story.pop() if story and isinstance(story[-1], Paragraph) else None
        if heading:
            story.append(PageBreak())
        img = Image(str(ROOT / match[2]))
        native_height, native_width = img.imageHeight, img.imageWidth
        img.drawWidth = CONTENT_W
        img.drawHeight = CONTENT_W * native_height / native_width
        if img.drawHeight > PAGE_H - 83:
            ratio = (PAGE_H - 83) / img.drawHeight
            img.drawWidth *= ratio
            img.drawHeight *= ratio
        img.hAlign = 'CENTER'
        story.append(img)
        story.append(PageBreak())
        if heading:
            story.append(heading)
    elif line.startswith('|'):
        table_lines = []
        while i < len(lines) and lines[i].strip().startswith('|'):
            table_lines.append(lines[i])
            i += 1
        story.append(make_table(table_lines))
        continue
    elif line.startswith('```'):
        i += 1
        code_lines = []
        while i < len(lines) and not lines[i].strip().startswith('```'):
            code_lines.append(html.escape(lines[i]).replace('  ', '&nbsp;&nbsp;'))
            i += 1
        story.append(KeepTogether([Paragraph('<br/>'.join(code_lines), code)]))
    elif re.match(r'^\d+\.\s', line):
        story.append(Paragraph(markup(line), bullet))
    else:
        text = [line]
        while (i + 1 < len(lines) and lines[i + 1].strip()
               and not lines[i + 1].lstrip().startswith(('#', '|', '![', '```'))
               and not re.match(r'^\d+\.\s', lines[i + 1])):
            i += 1
            text.append(lines[i].strip())
        story.append(Paragraph(markup(' '.join(text)), body))
    i += 1


def page_chrome(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor('#DCE5ED'))
    canvas.line(MARGIN_X, PAGE_H - 27, PAGE_W - MARGIN_X, PAGE_H - 27)
    canvas.setFont('Korean', 7.3)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN_X, PAGE_H - 20, 'MAMMOTH  |  죽음 연출 콘티와 기능명세서')
    canvas.drawRightString(PAGE_W - MARGIN_X, PAGE_H - 20, '기획 제안  ·  2026.09.30')
    canvas.drawString(MARGIN_X, 20, '카메라 / VFX / 사운드 / 엔진 연결 / 복원 / QA')
    canvas.drawRightString(PAGE_W - MARGIN_X, 20, str(doc.page))
    canvas.restoreState()


doc = SimpleDocTemplate(str(OUTPUT), pagesize=landscape(A4),
                        leftMargin=MARGIN_X, rightMargin=MARGIN_X,
                        topMargin=35, bottomMargin=35,
                        title='맘모스 보스 죽음 연출 콘티와 기능명세서',
                        author='Neon Arena 제작 기획', pageCompression=1)
doc.build(story, onFirstPage=page_chrome, onLaterPages=page_chrome)
reader = PdfReader(OUTPUT)
texts = [p.extract_text() or '' for p in reader.pages]
required = ['코어 과부하', '궤도 파손과 전복', '전원 붕괴와 마지막 파열',
            '공통 실행 계약', '시간과 속성 소유권', '검증과 승인 기준',
            '복원과 실패 처리', '성능 예산과 품질 단계']
full_text = '\n'.join(texts)
missing = [term for term in required if term not in full_text]
if missing:
    raise RuntimeError(f'PDF content missing: {missing}')
report = {'pdf': str(OUTPUT), 'pages': len(reader.pages),
          'source_chars': len(SOURCE.read_text(encoding='utf-8')),
          'pdf_text_chars': len(full_text), 'required_terms_verified': required,
          'page_text_lengths': [len(t) for t in texts]}
qa_dir = PROJECT / 'tmp' / 'pdfs' / 'mammoth-death'
qa_dir.mkdir(parents=True, exist_ok=True)
(qa_dir / 'text-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2),
                                           encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
