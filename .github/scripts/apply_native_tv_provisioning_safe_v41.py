from pathlib import Path
import re

ROOT = Path('native-tv-complete')
PROVISIONING = ROOT / 'app/src/main/java/com/tvfull/pro/ProvisioningActivity.kt'
GRADLE = ROOT / 'app/build.gradle'


def load(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


prov = load(PROVISIONING)

# V4.1 intentionally returns to the simple, proven LinearLayout structure from
# the working provisioning screen. The only responsive change is that every
# content row uses MATCH_PARENT inside safe TV margins; no ScrollView, no
# calculated child width and no pre-attachment focus request are used.
new_build_ui = r'''    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(36), dp(18), dp(36), dp(18))
            setBackgroundColor(Color.rgb(7, 11, 18))
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(16), dp(24), dp(16))
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(13, 20, 30), Color.rgb(8, 20, 34))
            ).apply {
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), Color.rgb(35, 48, 67))
            }
        }

        card.addView(TextView(this).apply {
            text = "TV FULL PRO"
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 1
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        card.addView(TextView(this).apply {
            text = "ACTIVACIÓN REMOTA"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(22, 168, 255))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            letterSpacing = 0.06f
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(4)
        })

        card.addView(TextView(this).apply {
            text = "Vinculá este televisor desde el panel de TV FULL.\nLas listas y servicios se cargarán automáticamente."
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })

        codeText = TextView(this).apply {
            text = "GENERANDO CÓDIGO…"
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 1
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(14, 31, 48), Color.rgb(8, 59, 94))
            ).apply {
                cornerRadius = dp(16).toFloat()
                setStroke(dp(2), Color.rgb(22, 168, 255))
            }
        }
        card.addView(codeText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(12)
        })

        statusText = TextView(this).apply {
            text = "Registrando dispositivo…"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 193, 204))
            maxLines = 3
            setPadding(dp(6), dp(6), dp(6), dp(6))
        }
        card.addView(statusText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(6)
        })

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        retry = tvButton("REINTENTAR") {
            handler.removeCallbacks(poll)
            val credentials = RemotePrefs.loadCredentials(this)
            if (credentials == null) registerDevice() else syncNow()
        }
        actions.addView(retry, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginEnd = dp(8) })

        actions.addView(tvButton("CONFIGURACIÓN MANUAL") {
            RemotePrefs.disableRemote(this)
            startActivity(Intent(this, LoginActivity::class.java).putExtra("force_login", true))
            finish()
        }, LinearLayout.LayoutParams(0, dp(50), 1.35f))

        card.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(10)
        })

        card.addView(TextView(this).apply {
            text = "El televisor consulta el panel automáticamente."
            textSize = 10f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(130, 142, 160))
            maxLines = 2
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })

        root.addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        return root
    }

'''
updated, count = re.subn(
    r'    private fun buildUi\(\): View \{.*?\n    \}\n\n(?=    private fun tvButton)',
    new_build_ui,
    prov,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'safe provisioning UI: expected exactly 1 match, found {count}')
save(PROVISIONING, updated)

gradle = load(GRADLE)
gradle = replace_once(gradle, 'versionCode 10', 'versionCode 11', 'V4.1 version code')
gradle = replace_once(
    gradle,
    "versionName '4.0-native-tv-stability'",
    "versionName '4.1-native-tv-stability-safe-provisioning'",
    'V4.1 version name',
)
save(GRADLE, gradle)

print('Native TV V4.1 safe provisioning screen applied successfully.')
