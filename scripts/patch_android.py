from pathlib import Path
import re

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('AndroidManifest.xml not found. Run flutter create --platforms=android . first.')

text = manifest.read_text(encoding='utf-8')

perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
]
for perm in perms:
    if f'android:name="{perm}"' not in text:
        text = text.replace('<manifest ', '<manifest ' + f'\n    <uses-permission android:name="{perm}" />', 1)

if 'android:usesCleartextTraffic=' not in text:
    text = re.sub(r'<application\b', '<application android:usesCleartextTraffic="true"', text, count=1)

manifest.write_text(text, encoding='utf-8')
print(f'Patched {manifest}')
