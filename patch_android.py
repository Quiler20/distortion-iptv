import re, pathlib

root = pathlib.Path('android/app')

# 1) minSdk
for name in ('build.gradle', 'build.gradle.kts'):
    f = root / name
    if f.exists():
        s = f.read_text()
        s = re.sub(r'minSdk(Version)?(\s*=\s*|\s+)flutter\.minSdkVersion', 'minSdk = 23', s)
        f.write_text(s)

# 2) Manifest
m = root / 'src/main/AndroidManifest.xml'
s = m.read_text()
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
if 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' not in s:
    perms = ''.join(
        f'    <uses-permission android:name="android.permission.{p}"/>\n'
        for p in ['INTERNET', 'WAKE_LOCK', 'FOREGROUND_SERVICE',
                  'FOREGROUND_SERVICE_MEDIA_PLAYBACK', 'POST_NOTIFICATIONS'])
    s = s.replace('<application', perms + '    <application', 1)
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
if 'AudioService' not in s:
    block = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>
    </application>'''
    s = s.replace('</application>', block, 1)
m.write_text(s)

# 3) MainActivity
for f in (root / 'src/main').rglob('MainActivity.*'):
    if f.suffix == '.kt':
        pkg = re.search(r'package\s+([\w.]+)', f.read_text()).group(1)
        f.write_text(
            f'package {pkg}\n\n'
            'import com.ryanheise.audioservice.AudioServiceActivity\n\n'
            'class MainActivity : AudioServiceActivity()\n')
print('Android parcheado OK')
