from pathlib import Path
import re
import shutil

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('AndroidManifest.xml not found. Run flutter create --platforms=android . first.')

text = manifest.read_text(encoding='utf-8')
text = re.sub(r'android:label="[^"]*"', 'android:label="BersolekMart"', text, count=1)

permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.CAMERA',
]
missing = [
    f'    <uses-permission android:name="{permission}" />'
    for permission in permissions
    if f'android:name="{permission}"' not in text
]
if missing:
    # Permissions must be siblings of <application>, inside <manifest>.
    marker = re.search(r'<application\b', text)
    if marker is None:
        raise SystemExit('AndroidManifest.xml has no <application> element.')
    text = text[:marker.start()] + '\n'.join(missing) + '\n    ' + text[marker.start():]

if 'android:usesCleartextTraffic=' in text:
    text = re.sub(
        r'android:usesCleartextTraffic="[^"]*"',
        'android:usesCleartextTraffic="false"',
        text,
        count=1,
    )
else:
    text = re.sub(r'<application\b', '<application android:usesCleartextTraffic="false"', text, count=1)

manifest.write_text(text, encoding='utf-8')

# Flutter recreates the Android folder in CI. Keep launch branding deterministic
# by patching the generated Android launch theme at build time.
res = Path('android/app/src/main/res')
branding_mark = Path('assets/branding/bersolek-mart-adaptive-foreground.png')
if not branding_mark.exists():
    raise SystemExit(f'BersolekMart launch mark not found: {branding_mark}')

drawable_nodpi = res / 'drawable-nodpi'
drawable_nodpi.mkdir(parents=True, exist_ok=True)
shutil.copyfile(branding_mark, drawable_nodpi / 'bersolekmart_launch_icon.png')

colors = res / 'values' / 'colors.xml'
colors.parent.mkdir(parents=True, exist_ok=True)
if colors.exists():
    colors_text = colors.read_text(encoding='utf-8')
    if 'name="bersolekmart_splash_background"' in colors_text:
        colors_text = re.sub(
            r'<color name="bersolekmart_splash_background">[^<]*</color>',
            '<color name="bersolekmart_splash_background">#17090D</color>',
            colors_text,
        )
    else:
        colors_text = colors_text.replace(
            '</resources>',
            '    <color name="bersolekmart_splash_background">#17090D</color>\n</resources>',
        )
else:
    colors_text = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bersolekmart_splash_background">#17090D</color>
</resources>
'''
colors.write_text(colors_text, encoding='utf-8')

launch_background = res / 'drawable' / 'launch_background.xml'
launch_background.parent.mkdir(parents=True, exist_ok=True)
launch_background.write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/bersolekmart_splash_background" />
    <item android:width="144dp" android:height="144dp" android:gravity="center">
        <bitmap android:src="@drawable/bersolekmart_launch_icon" android:gravity="center" />
    </item>
</layer-list>
''', encoding='utf-8')

def patch_style(style_path: Path, android12: bool = False) -> None:
    if not style_path.exists():
        return
    styles = style_path.read_text(encoding='utf-8')
    match = re.search(r'(<style\s+name="LaunchTheme"[^>]*>)(.*?)(</style>)', styles, re.S)
    if match is None:
        print(f'WARN: no LaunchTheme found in {style_path}; leaving its theme definitions intact.')
        return
    body = match.group(2)
    def put_item(name: str, value: str, body_text: str) -> str:
        pattern = rf'<item\s+name="{re.escape(name)}">.*?</item>'
        item = f'<item name="{name}">{value}</item>'
        if re.search(pattern, body_text, re.S):
            return re.sub(pattern, item, body_text, count=1, flags=re.S)
        return body_text.rstrip() + '\n        ' + item + '\n    '
    if android12:
        body = put_item('android:windowSplashScreenBackground', '@color/bersolekmart_splash_background', body)
        body = put_item('android:windowSplashScreenAnimatedIcon', '@drawable/bersolekmart_launch_icon', body)
        body = put_item('android:windowSplashScreenIconBackgroundColor', '@color/bersolekmart_splash_background', body)
    else:
        body = put_item('android:windowBackground', '@drawable/launch_background', body)
    styles = styles[:match.start(2)] + body + styles[match.end(2):]
    style_path.write_text(styles, encoding='utf-8')

patch_style(res / 'values' / 'styles.xml')
patch_style(res / 'values-v31' / 'styles.xml', android12=True)

print(f'Patched Android manifest and branded launch themes under {res}')
