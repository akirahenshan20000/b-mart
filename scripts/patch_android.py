from pathlib import Path
import re

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
]
missing = [
    f'    <uses-permission android:name="{permission}" />'
    for permission in permissions
    if f'android:name="{permission}"' not in text
]
if missing:
    # Permissions must be sibling elements of <application>, not inserted
    # into the opening <manifest> tag where they would corrupt its XML attributes.
    marker = re.search(r'<application\\b', text)
    if marker is None:
        raise SystemExit('AndroidManifest.xml has no <application> element.')
    text = text[:marker.start()] + '\\n'.join(missing) + '\\n    ' + text[marker.start():]

if 'android:usesCleartextTraffic=' not in text:
    text = re.sub(r'<application\\b', '<application android:usesCleartextTraffic="true"', text, count=1)

manifest.write_text(text, encoding='utf-8')
print(f'Patched {manifest}')
