from pathlib import Path

path = Path('lib/widgets/live_video_view.dart')
text = path.read_text(encoding='utf-8')
old = "final value = currentMs.toDouble().clamp(0, max);"
new = "final value = currentMs.toDouble().clamp(0.0, max).toDouble();"
if old not in text:
    raise SystemExit('slider value pattern not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('premium player slider type fixed')
