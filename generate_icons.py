"""Resize app icon cho tất cả mipmap Android sizes"""
from PIL import Image
import os

# Source icon
src = r"E:\xem phim tren motchill\xem phim Kh.le online\khle_app\app_icon.png"
base = r"E:\xem phim tren motchill\xem phim Kh.le online\khle_app\android\app\src\main\res"

# Android mipmap sizes
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

img = Image.open(src).convert("RGBA")

for folder, size in sizes.items():
    out_dir = os.path.join(base, folder)
    os.makedirs(out_dir, exist_ok=True)
    
    # Resize with high quality
    resized = img.resize((size, size), Image.LANCZOS)
    
    # Save as ic_launcher.png
    out_path = os.path.join(out_dir, "ic_launcher.png")
    resized.save(out_path, "PNG")
    print(f"  {folder}: {size}x{size} -> {out_path}")

print("\nDone! All icons generated.")
