# tvhome C06 — mon fork de tv-detox

Un écran d'accueil Android TV minimal pour ma **TCL C06** (Google TV, Android 11, 1280 × 720,
armeabi-v7a), et les outils de débloat qui vont avec.

C'est un fork de [Ansub/tv-detox](https://github.com/Ansub/tv-detox) : l'upstream fournit le
launcher `com.ansub.tvhome`, les scripts de débloat (`candidates.sh`, `check.sh`, `undo.sh`) et la
documentation d'origine. Ce fork garde tout ça, plus ma propre version de l'écran d'accueil et
mes instructions.

## L'APK

Dernière version : **[v1.3.1-c06](https://github.com/Potowai/tv-detox/releases/latest)** —
`tvhome.apk`, signé, `versionCode` 11, Android 9+.

```bash
adb install -r tvhome.apk
adb shell cmd package set-home-activity --user 0 com.ansub.tvhome/.MainActivity
```

Sous Windows, les deux scripts s'en occupent (désinstallation de l'ancienne build, installation,
rangée, rôle HOME) :

```powershell
powershell -ExecutionPolicy Bypass -File install-tvhome.ps1 -Ip 192.168.1.50
powershell -ExecutionPolicy Bypass -File set-default-home.ps1 -Ip 192.168.1.50
```

## Ce que cette version change par rapport à l'upstream 1.3.0

- **Trois cartes par ligne** au lieu de six, format 464 × 220 en 1920 × 1080, l'icône réelle de
  l'app à gauche et son nom à droite — aucune bannière, aucun visuel dessiné.
- **Focus** : bordure 2 px `#72A7FF`, halo bleu, échelle 1.025, 160 ms.
- **Une seule barre en bas** : Accueil (souligné), HDMI 1, HDMI 2, Play Store, Paramètres,
  Ajouter une app, avec séparateurs. Elle ne défile pas avec les apps.
- **En-tête** : date en toutes lettres, horloge 68 px en light, Wi-Fi et engrenage à droite.
- **Fond photo embarqué** (`assets/wallpaper.jpg`), assombri, avec un voile marine qui s'épaissit
  vers le bas. Si l'asset manque, retour au dégradé : jamais d'écran noir.
- **Rangée qui s'auto-complète** : une app installée après l'enregistrement de la rangée y entre
  toute seule (`PackageInfo.firstInstallTime`). Une rangée enregistrée ne bouge pas autrement.
- **`apps.txt` de départ** : TF1+, SmartTube, Nuvio.

## Construire

**Windows** (sans Gradle) :

```powershell
$env:ANDROID_SDK = "C:\Android\Sdk"     # build-tools 36.1 + platform android-34
$env:JAVA_HOME   = "C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot"
powershell -ExecutionPolicy Bypass -File build.ps1
# -> out\tvhome.apk
```

**macOS / Linux** :

```bash
./build.sh            # JDK 17+, Android SDK, build-tools 34.0.0
```

Notes de terrain :

- `d8` de build-tools **34.0.0** plante sur les classes du JDK 21 (`NullPointerException` dans
  `MethodParameters`). Prendre **36.1**, ou compiler avec un JDK 17.
- `javac` 21 refuse `-bootclasspath` : `build.ps1` réessaie avec `-classpath`.
- Sans `aapt2 link -A assets`, l'APK se construit mais la photo de fond manque.
- La clé de signature est **hors du dépôt** (`TVHOME_KEYSTORE` pour `build.ps1`, `KEYSTORE` pour
  `build.sh`). Changer de clé oblige à désinstaller l'ancienne build : Android refuse une mise à
  jour signée autrement, et la désinstallation efface la rangée enregistrée.

## Débloat

Rien n'a été réécrit : les scripts de l'upstream restent la référence.

```bash
./check.sh                # état actuel : désactivées, suspendues, RAM
./candidates.sh           # liste des paquets candidats, avec un avis par paquet
./install.sh              # désactive (jamais désinstalle) la liste retenue
./undo.sh                 # remet tout
```

Voir [`docs/debloat.md`](docs/debloat.md) pour la méthode et les pièges (paquets `PERSISTENT`,
liste de retour, vérification du Chromecast après chaque vague).

## Sur ma télé

| | |
|---|---|
| TV | TCL C06, Android 11 (API 30), 1280 × 720 |
| Accueil | `com.ansub.tvhome` (ce fork) |
| Gardés volontairement | Chromecast (`mediashell`, `gms`), TF1+, SmartTube, Nuvio, Downloader |
| Désactivés | 47 paquets |
| Suspendus | 2 paquets `PERSISTENT` TCL |

## Licence et crédits

MIT, voir [`LICENSE`](LICENSE) — le copyright d'origine (Ansub Khan) est conservé.
Le README complet de l'upstream est gardé dans [`README.upstream.md`](README.upstream.md).
Fond d'écran : « Nautical twilight sunset over Sandy Lake » par **Trougnouf**, CC BY 4.0,
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Nautical_twilight_sunset_over_Sandy_Lake_(DSCF3005).jpg)
— recadré en 1280 × 720 et assombri.
