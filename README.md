# Distortion Labs IPTV (Flutter)

## 1. Crear el proyecto base
```bash
flutter create --org com.distortionlabs --project-name distortion_labs_iptv .
```
Ejecútalo dentro de esta carpeta (no sobrescribe `lib/` ni `pubspec.yaml`). Luego:
```bash
flutter pub get
```

## 2. Android (necesario para pantalla apagada)

**android/app/build.gradle** → `minSdkVersion 21` (o `minSdk = 21`).

**android/app/src/main/kotlin/.../MainActivity.kt**
```kotlin
import com.ryanheise.audioservice.AudioServiceActivity
class MainActivity : AudioServiceActivity()
```

**android/app/src/main/AndroidManifest.xml**
Añade en `<manifest>` (y `xmlns:tools="http://schemas.android.com/tools"` en la etiqueta):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
En `<application>` añade `android:usesCleartextTraffic="true"` (muchos IPTV usan http) y, dentro:
```xml
<service android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true" tools:ignore="Instantiatable">
  <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
</service>
<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true" tools:ignore="Instantiatable">
  <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
</receiver>
```

## 3. iOS (requiere Mac)
**ios/Runner/Info.plist**
```xml
<key>UIBackgroundModes</key><array><string>audio</string></array>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

## 4. Ejecutar / compilar
```bash
flutter run
flutter build apk --release
```

## Funciones
- Listas: URL, pegar M3U, archivo del celular, Xtream Codes; agregar, eliminar, actualizar.
- Canales con búsqueda y filtro por grupo; favoritos.
- Reproductor: menú de canales lateral, anterior/siguiente, ampliar/reducir (botones o pellizco), ajuste (Ajustar/Llenar/Estirar), girar.
- Bloqueo táctil (mantén pulsado el candado para desbloquear).
- Modo audio (icono auriculares): la pantalla se apaga sola y el audio sigue con notificación de control. Funciona también al bloquear con el botón de encendido.
- Icono de escoba: limpia caché de listas e imágenes y recarga la lista activa.
