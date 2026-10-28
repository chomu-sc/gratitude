#!/usr/bin/env python3
"""노란 스마일 앱 아이콘 생성기 → Assets.xcassets/AppIcon.appiconset

- iOS: 1024×1024 단일 이미지 (불투명 정사각형, 모서리는 시스템이 자동으로 둥글게 처리)
- macOS: 16~1024 전 사이즈, Big Sur 이후 규격(824px 둥근 사각형 + 여백 + 그림자)

사용법:  python3 Scripts/generate_icon.py   (pip install pillow)
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "GratitudeJournal/Resources/Assets.xcassets/AppIcon.appiconset"
SS = 4  # 슈퍼샘플링 배율 (부드러운 가장자리)

TOP = (255, 221, 77)      # 밝은 노랑
BOTTOM = (255, 176, 32)   # 따뜻한 주황빛 노랑
INK = (74, 52, 18)        # 진한 갈색 (검정보다 부드러움)


def gradient(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def draw_face(d, cx, cy, s):
    """s = 얼굴 기준 크기(정사각형 한 변)"""
    ew, eh = s * 0.085, s * 0.15
    for ex in (cx - s * 0.15, cx + s * 0.15):
        d.rounded_rectangle([ex - ew / 2, cy - s * 0.17 - eh / 2, ex + ew / 2, cy - s * 0.17 + eh / 2],
                            radius=ew / 2, fill=INK)
    # 미소: 아래쪽 호
    w, lw = s * 0.46, s * 0.055
    box = [cx - w / 2, cy - s * 0.12, cx + w / 2, cy + s * 0.25]
    d.arc(box, start=20, end=160, fill=INK, width=int(lw))
    # 둥근 입꼬리
    import math
    rx, ry = w / 2, (box[3] - box[1]) / 2
    ocx, ocy = cx, (box[1] + box[3]) / 2
    for ang in (20, 160):
        a = math.radians(ang)
        px, py = ocx + (rx - lw / 2) * math.cos(a), ocy + (ry - lw / 2) * math.sin(a)
        d.ellipse([px - lw / 2, py - lw / 2, px + lw / 2, py + lw / 2], fill=INK)


def ios_icon(size=1024):
    big = size * SS
    img = gradient(big)
    # 은은한 하이라이트
    hl = Image.new("L", (big, big), 0)
    ImageDraw.Draw(hl).ellipse([big * 0.1, -big * 0.35, big * 0.9, big * 0.45], fill=60)
    img = Image.composite(Image.new("RGB", (big, big), (255, 255, 255)), img, hl.filter(ImageFilter.GaussianBlur(big * 0.06)))
    draw_face(ImageDraw.Draw(img), big / 2, big / 2 + big * 0.04, big)
    return img.resize((size, size), Image.LANCZOS)


def mac_icon(size=1024):
    big = size * SS
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    body = big * 824 / 1024
    off = (big - body) / 2
    radius = body * 0.225
    # 그림자
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([off, off + big * 0.012, off + body, off + body + big * 0.012],
                                             radius=radius, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(big * 0.012)))
    # 본체
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([off, off, off + body, off + body], radius=radius, fill=255)
    fill = gradient(big).convert("RGBA")
    canvas.paste(fill, (0, 0), mask)
    draw_face(ImageDraw.Draw(canvas), big / 2, big / 2 + body * 0.04, body)
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = []

    ios_icon().save(OUT / "icon-ios-1024.png")
    images.append({"filename": "icon-ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})

    master = mac_icon(1024)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon-mac-{pt}@{scale}x.png"
            master.resize((px, px), Image.LANCZOS).save(OUT / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})

    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
    (OUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    print(f"✅ {len(images)}개 아이콘 → {OUT}")


if __name__ == "__main__":
    main()
