from pathlib import Path

ROOT = Path('.')
GRADLE = ROOT / 'android/app/build.gradle.kts'
MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'


def main():
    if not GRADLE.exists() or not MANIFEST.exists():
        raise SystemExit('Android project missing')

    g = GRADLE.read_text()
    old = 'applicationId = "com.tvfull.pro.tv.v6texture"'
    new = 'applicationId = "com.tvfull.pro.tv.v7integrated"'
    if old not in g:
        raise SystemExit('Expected V6 package id not found')
    g = g.replace(old, new, 1)
    GRADLE.write_text(g)

    m = MANIFEST.read_text()
    m = m.replace('TV FULL PRO V6 TEXTURE', 'TV FULL PRO V7', 1)
    MANIFEST.write_text(m)

    print('V7 install compatibility applied: new package id, ARM32+ARM64 build will avoid V6 signature collision.')


if __name__ == '__main__':
    main()
