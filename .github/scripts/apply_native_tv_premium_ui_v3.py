from pathlib import Path
import re

ROOT = Path('native-tv-complete')
SRC = ROOT / 'app/src/main/java/com/tvfull/pro'
TV = SRC / 'TvHomeActivity.kt'
PLAYLIST = SRC / 'PlaylistActivity.kt'
PROVISIONING = SRC / 'ProvisioningActivity.kt'


def load(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def save(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


def replace_regex(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return updated


tv = load(TV)

# ---------------------------------------------------------------------------
# Layout proportions: more breathing room and a Mac-like navigation rail.
# ---------------------------------------------------------------------------
tv = replace_once(
    tv,
    'root.addView(topBar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)))',
    'root.addView(topBar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(78)))',
    'premium top bar height',
)
tv = replace_once(
    tv,
    'body.addView(navRail, LinearLayout.LayoutParams(dp(154), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })',
    'body.addView(navRail, LinearLayout.LayoutParams(dp(190), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(12) })',
    'premium nav width',
)
tv = replace_once(
    tv,
    'body.addView(browsePanel, LinearLayout.LayoutParams(dp(400), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(10) })',
    'body.addView(browsePanel, LinearLayout.LayoutParams(dp(390), ViewGroup.LayoutParams.MATCH_PARENT).apply { marginEnd = dp(12) })',
    'premium browse width',
)

# Section controls become custom TextViews, eliminating generic Android Button chrome.
tv = replace_once(
    tv,
    'private val sectionButtons = linkedMapOf<ContentSection, Button>()',
    'private val sectionButtons = linkedMapOf<ContentSection, TextView>()',
    'section control type',
)

premium_top = r'''    private fun buildTopBar(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(22), dp(8), dp(20), dp(8))
            background = premiumSurface(TOP, BG, 0f, BORDER, 1)

            val logo = TextView(this@TvHomeActivity).apply {
                text = "▶"
                textSize = 20f
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD)
                background = premiumSurface(ACCENT, ACCENT_DEEP, 14f, Color.argb(150, 255, 255, 255), 1)
                elevation = dp(7).toFloat()
            }
            addView(logo, LinearLayout.LayoutParams(dp(54), dp(46)).apply { marginEnd = dp(13) })

            val brand = LinearLayout(this@TvHomeActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                addView(LinearLayout(this@TvHomeActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(TextView(this@TvHomeActivity).apply {
                        text = "TV FULL"
                        textSize = 20f
                        setTextColor(TEXT)
                        setTypeface(typeface, Typeface.BOLD)
                        letterSpacing = 0.02f
                    })
                    addView(TextView(this@TvHomeActivity).apply {
                        text = "PRO"
                        textSize = 13f
                        setTextColor(GOLD)
                        setTypeface(typeface, Typeface.BOLD)
                        setPadding(dp(7), 0, 0, 0)
                        letterSpacing = 0.08f
                    })
                })
                addView(TextView(this@TvHomeActivity).apply {
                    text = "NATIVE TV"
                    textSize = 9f
                    setTextColor(MUTED)
                    letterSpacing = 0.22f
                })
            }
            addView(brand, LinearLayout.LayoutParams(dp(190), ViewGroup.LayoutParams.MATCH_PARENT))

            val divider = View(this@TvHomeActivity).apply { setBackgroundColor(BORDER) }
            addView(divider, LinearLayout.LayoutParams(dp(1), dp(34)).apply { marginEnd = dp(18) })

            sectionTitle = TextView(this@TvHomeActivity).apply {
                text = "TV EN VIVO"
                textSize = 20f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
            }
            addView(sectionTitle, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))

            addView(TextView(this@TvHomeActivity).apply {
                text = RemotePrefs.serviceName(this@TvHomeActivity).ifBlank {
                    if (sourceConfig.mode == SourceMode.XTREAM) "XTREAM" else "M3U"
                }
                textSize = 11f
                setTextColor(Color.rgb(190, 204, 222))
                gravity = Gravity.CENTER
                setTypeface(typeface, Typeface.BOLD)
                background = premiumSurface(PANEL_ALT, PANEL, 18f, BORDER, 1)
            }, LinearLayout.LayoutParams(dp(176), dp(36)).apply { marginEnd = dp(14) })

            clock = TextView(this@TvHomeActivity).apply {
                textSize = 16f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            addView(clock, LinearLayout.LayoutParams(dp(72), ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }

'''
tv = replace_regex(
    tv,
    r'    private fun buildTopBar\(\): LinearLayout \{.*?\n    \}\n\n(?=    private fun buildNavRail)',
    premium_top,
    'premium top bar',
)

premium_nav = r'''    private fun buildNavRail(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), dp(14), dp(10), dp(12))
            background = premiumSurface(PANEL, BG, 18f, BORDER, 1)
            elevation = dp(3).toFloat()

            addView(TextView(this@TvHomeActivity).apply {
                text = "NAVEGACIÓN"
                textSize = 9f
                setTextColor(MUTED)
                setTypeface(typeface, Typeface.BOLD)
                letterSpacing = 0.15f
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), 0, 0, 0)
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(30)))

            addView(sectionButton(ContentSection.LIVE, "TV en vivo"))
            addView(sectionButton(ContentSection.MOVIES, "Películas"))
            addView(sectionButton(ContentSection.SERIES, "Series"))
            addView(sectionButton(ContentSection.RADIO, "Radio"))
            addView(navButton("Buscar") { showSearch() })

            addView(View(this@TvHomeActivity).apply { setBackgroundColor(BORDER) },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply {
                    topMargin = dp(8); bottomMargin = dp(10); marginStart = dp(8); marginEnd = dp(8)
                })

            addView(navButton("Mis listas") { openPlaylists() })
            addView(View(this@TvHomeActivity), LinearLayout.LayoutParams(1, 0, 1f))
            addView(navButton("Ajustes") { showSettings() })
        }
    }

'''
tv = replace_regex(
    tv,
    r'    private fun buildNavRail\(\): LinearLayout \{.*?\n    \}\n\n(?=    private fun buildBrowsePanel)',
    premium_nav,
    'premium navigation rail',
)

premium_browse = r'''    private fun buildBrowsePanel(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(13), dp(14), dp(12))
            background = premiumSurface(PANEL, Color.rgb(9, 15, 25), 18f, BORDER, 1)
            elevation = dp(3).toFloat()

            browseTitle = TextView(this@TvHomeActivity).apply {
                text = "CATEGORÍAS"
                textSize = 17f
                setTextColor(TEXT)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(browseTitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(34)))

            browseSubtitle = TextView(this@TvHomeActivity).apply {
                text = "Elegí una categoría"
                textSize = 11f
                setTextColor(MUTED)
                gravity = Gravity.CENTER_VERTICAL
                maxLines = 1
            }
            addView(browseSubtitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)))

            addView(View(this@TvHomeActivity).apply { setBackgroundColor(Color.argb(120, 35, 48, 67)) },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply { bottomMargin = dp(8) })

            recycler = RecyclerView(this@TvHomeActivity).apply {
                setBackgroundColor(Color.TRANSPARENT)
                setPadding(dp(2), dp(4), dp(2), dp(4))
                clipToPadding = false
                isVerticalScrollBarEnabled = false
                setItemViewCacheSize(2)
            }
            addView(recycler, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    }

'''
tv = replace_regex(
    tv,
    r'    private fun buildBrowsePanel\(\): LinearLayout \{.*?\n    \}\n\n(?=    private fun buildRightPanel)',
    premium_browse,
    'premium browse panel',
)

# HUD becomes a true translucent overlay rather than a flat opaque rectangle.
tv = replace_once(
    tv,
    'setBackgroundColor(Color.argb(220, 3, 6, 11))',
    'background = premiumSurface(Color.argb(242, 4, 9, 16), Color.argb(188, 7, 19, 31), 0f, Color.argb(90, 22, 168, 255), 1)',
    'premium HUD surface',
)
# Tint progress controls in the brand color.
tv = tv.replace(
    'isFocusable = false\n            }\n            liveProgressRow.addView',
    'isFocusable = false\n                progressTintList = android.content.res.ColorStateList.valueOf(ACCENT)\n                thumbTintList = android.content.res.ColorStateList.valueOf(ACCENT)\n            }\n            liveProgressRow.addView',
    1,
)
# Second SeekBar (VOD).
needle = '''            vodProgress = SeekBar(this@TvHomeActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
            }
'''
if needle in tv:
    tv = tv.replace(needle, '''            vodProgress = SeekBar(this@TvHomeActivity).apply {
                max = 1000
                isEnabled = false
                isFocusable = false
                progressTintList = android.content.res.ColorStateList.valueOf(ACCENT)
                thumbTintList = android.content.res.ColorStateList.valueOf(ACCENT)
            }
''', 1)

# Professional custom navigation controls.
tv = replace_regex(
    tv,
    r'    private fun sectionButton\(section: ContentSection, label: String\): Button =.*?\n    \}\n\n(?=    private fun showCategories)',
    r'''    private fun sectionButton(section: ContentSection, label: String): TextView =
        navButton(label) { showCategories(section) }.also { sectionButtons[section] = it }

    private fun navButton(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 13f
            gravity = Gravity.CENTER_VERTICAL
            setTypeface(typeface, Typeface.BOLD)
            isFocusable = true
            isClickable = true
            setTextColor(Color.rgb(194, 204, 219))
            setPadding(dp(14), 0, dp(10), 0)
            background = premiumSurface(Color.TRANSPARENT, Color.TRANSPARENT, 13f)
            setOnClickListener { action() }
            setOnFocusChangeListener { v, focused ->
                (v as TextView).apply {
                    setTextColor(if (focused) Color.WHITE else Color.rgb(194, 204, 219))
                    background = if (focused) {
                        premiumSurface(Color.rgb(8, 72, 116), Color.rgb(7, 43, 72), 13f, ACCENT, 2)
                    } else {
                        premiumSurface(Color.TRANSPARENT, Color.TRANSPARENT, 13f)
                    }
                    elevation = if (focused) dp(8).toFloat() else 0f
                    animate().scaleX(if (focused) 1.035f else 1f).scaleY(if (focused) 1.035f else 1f).setDuration(120).start()
                }
            }
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply { bottomMargin = dp(5) }
        }
    }

''',
    'premium nav controls',
)

# Current section should use the same premium language even when focus moves away.
tv = tv.replace(
    'b.background = rounded(if (s == section) Color.rgb(7, 55, 92) else Color.TRANSPARENT, 10f, if (s == section) ACCENT else null, if (s == section) 1 else 0)',
    'b.background = if (s == section) premiumSurface(Color.rgb(6, 47, 78), Color.rgb(8, 32, 52), 13f, Color.argb(145, 22, 168, 255), 1) else premiumSurface(Color.TRANSPARENT, Color.TRANSPARENT, 13f)',
)

# Movie/series primary actions: custom surface, no generic Button widget look.
tv = replace_regex(
    tv,
    r'    private fun actionButton\(textValue: String, action: \(\) -> Unit\): Button = Button\(this\)\.apply \{.*?\n    \}\n\n(?=    private fun configurePanels)',
    r'''    private fun actionButton(textValue: String, action: () -> Unit): TextView = TextView(this).apply {
        text = textValue
        textSize = 13f
        gravity = Gravity.CENTER
        setTypeface(typeface, Typeface.BOLD)
        isFocusable = true
        isClickable = true
        setTextColor(Color.WHITE)
        background = premiumSurface(ACCENT, ACCENT_DEEP, 13f, Color.argb(130, 255, 255, 255), 1)
        elevation = dp(4).toFloat()
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as TextView).apply {
                background = if (focused)
                    premiumSurface(Color.rgb(42, 187, 255), ACCENT_DEEP, 13f, Color.WHITE, 2)
                else premiumSurface(ACCENT, ACCENT_DEEP, 13f, Color.argb(130, 255, 255, 255), 1)
                elevation = if (focused) dp(10).toFloat() else dp(4).toFloat()
                animate().scaleX(if (focused) 1.04f else 1f).scaleY(if (focused) 1.04f else 1f).setDuration(120).start()
            }
        }
    }

''',
    'premium action buttons',
)

# Settings buttons also stop using default Android button visuals.
tv = replace_regex(
    tv,
    r'    private fun settingsButton\(label: String, action: \(\) -> Unit\) = Button\(this\)\.apply \{.*?\n    \}\n\n(?=    private fun openPlaylists)',
    r'''    private fun settingsButton(label: String, action: () -> Unit) = TextView(this).apply {
        text = label
        textSize = 12f
        gravity = Gravity.CENTER
        setTypeface(typeface, Typeface.BOLD)
        isFocusable = true
        isClickable = true
        setTextColor(Color.WHITE)
        background = premiumSurface(CARD, PANEL_ALT, 11f, BORDER, 1)
        setOnClickListener { action() }
        setOnFocusChangeListener { v, focused ->
            (v as TextView).apply {
                background = if (focused)
                    premiumSurface(Color.rgb(7, 69, 111), Color.rgb(8, 39, 66), 11f, ACCENT, 2)
                else premiumSurface(CARD, PANEL_ALT, 11f, BORDER, 1)
                elevation = if (focused) dp(7).toFloat() else 0f
            }
        }
    }

''',
    'premium settings buttons',
)

# Gradient helper used throughout premium surfaces.
rounded_anchor = '    private fun rounded(fill: Int, radius: Float, stroke: Int? = null, strokeWidth: Int = 0): GradientDrawable =\n'
if rounded_anchor not in tv:
    raise SystemExit('rounded helper anchor missing')
premium_helper = r'''    private fun premiumSurface(
        start: Int,
        end: Int,
        radius: Float,
        stroke: Int? = null,
        strokeWidth: Int = 0
    ): GradientDrawable = GradientDrawable(
        GradientDrawable.Orientation.TL_BR,
        intArrayOf(start, end)
    ).apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(radius.toInt()).toFloat()
        if (stroke != null && strokeWidth > 0) setStroke(dp(strokeWidth), stroke)
    }

'''
tv = replace_once(tv, rounded_anchor, premium_helper + rounded_anchor, 'premium surface helper')

# Category cards: depth, restrained focus, animation.
tv = replace_once(
    tv,
    'background = rounded(CARD, 9f, BORDER, 1)\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)).apply { bottomMargin = dp(6) }',
    'background = premiumSurface(CARD, PANEL_ALT, 13f, BORDER, 1)\n                elevation = dp(2).toFloat()\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)).apply { bottomMargin = dp(7) }',
    'premium category base',
)
# Professional V2 already changed the exact focus line to ACCENT_DEEP.
tv = tv.replace(
    '(v as TextView).background = rounded(if (focused) ACCENT_DEEP else CARD, 10f, if (focused) ACCENT else BORDER, if (focused) 2 else 1)',
    '''(v as TextView).apply {
                    background = if (focused)
                        premiumSurface(Color.rgb(8, 67, 108), Color.rgb(8, 36, 61), 13f, ACCENT, 2)
                    else premiumSurface(CARD, PANEL_ALT, 13f, BORDER, 1)
                    elevation = if (focused) dp(9).toFloat() else dp(2).toFloat()
                    animate().scaleX(if (focused) 1.025f else 1f).scaleY(if (focused) 1.025f else 1f).setDuration(120).start()
                }''',
    1,
)

# Content list/grid cards.
tv = replace_once(
    tv,
    'background = rounded(CARD, 9f, BORDER, 1)\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62)).apply { bottomMargin = dp(6) }',
    'background = premiumSurface(CARD, PANEL_ALT, 13f, BORDER, 1)\n                elevation = dp(2).toFloat()\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(68)).apply { bottomMargin = dp(7) }',
    'premium list card',
)
tv = replace_once(
    tv,
    'background = rounded(CARD, 10f, BORDER, 1)\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(250)).apply {',
    'background = premiumSurface(CARD, PANEL_ALT, 14f, BORDER, 1)\n                elevation = dp(3).toFloat()\n                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(260)).apply {',
    'premium grid card',
)
tv = replace_once(
    tv,
    'background = rounded(PANEL_ALT, 8f)',
    'background = premiumSurface(Color.rgb(8, 13, 22), Color.rgb(13, 21, 34), 10f)',
    'premium poster surface',
)
# Replace content focus handler body (original red survives Professional V2 here).
tv = replace_regex(
    tv,
    r'''            holder\.root\.setOnFocusChangeListener \{ v, focused ->\n                v\.background = .*?\n                if \(focused\) showItemInfo\(item\)\n            \}''',
    r'''            holder.root.setOnFocusChangeListener { v, focused ->
                v.background = if (focused)
                    premiumSurface(Color.rgb(7, 57, 92), Color.rgb(9, 29, 48), if (grid) 14f else 13f, ACCENT, 2)
                else premiumSurface(CARD, PANEL_ALT, if (grid) 14f else 13f, BORDER, 1)
                v.elevation = if (focused) dp(10).toFloat() else dp(if (grid) 3 else 2).toFloat()
                v.animate().scaleX(if (focused) 1.035f else 1f).scaleY(if (focused) 1.035f else 1f).setDuration(120).start()
                if (focused) showItemInfo(item)
            }''',
    'premium content focus',
)

save(TV, tv)

# ---------------------------------------------------------------------------
# Playlist selector: same premium visual language.
# ---------------------------------------------------------------------------
playlist = load(PLAYLIST)
playlist = playlist.replace('setPadding(dp(28), dp(22), dp(28), dp(18))', 'setPadding(dp(42), dp(30), dp(42), dp(24))', 1)
playlist = playlist.replace('textSize = 31f', 'textSize = 34f', 1)
playlist = playlist.replace('layoutParams = RecyclerView.LayoutParams(dp(190), dp(132))', 'layoutParams = RecyclerView.LayoutParams(dp(220), dp(150))', 1)
playlist = playlist.replace('background = rounded(CARD, 16f, BORDER)', 'background = rounded(CARD, 18f, BORDER)', 1)
playlist = playlist.replace(
    'v.background = rounded(if (focused) Color.rgb(70, 20, 30) else CARD, 16f, if (focused) ACCENT else BORDER, if (focused) 3 else 1)',
    '''v.background = rounded(if (focused) Color.rgb(7, 58, 94) else CARD, 18f, if (focused) ACCENT else BORDER, if (focused) 3 else 1)
                v.elevation = if (focused) dp(10).toFloat() else dp(2).toFloat()
                v.animate().scaleX(if (focused) 1.05f else 1f).scaleY(if (focused) 1.05f else 1f).setDuration(120).start()''',
    1,
)
save(PLAYLIST, playlist)

# ---------------------------------------------------------------------------
# Provisioning: cleaner activation card hierarchy without changing behavior.
# ---------------------------------------------------------------------------
prov = load(PROVISIONING)
prov = prov.replace('setPadding(dp(70), dp(40), dp(70), dp(40))', 'setPadding(dp(96), dp(48), dp(96), dp(48))', 1)
prov = prov.replace('textSize = 38f', 'textSize = 40f', 1)
prov = prov.replace('setBackgroundColor(Color.rgb(30, 43, 65))', 'background = android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TL_BR, intArrayOf(Color.rgb(14, 31, 48), Color.rgb(8, 59, 94))).apply { cornerRadius = dp(18).toFloat(); setStroke(dp(2), Color.rgb(22, 168, 255)) }', 1)
prov = prov.replace('LinearLayout.LayoutParams(dp(680), dp(90))', 'LinearLayout.LayoutParams(dp(700), dp(104))', 1)
save(PROVISIONING, prov)

print('Native TV Premium UI V3 patch applied successfully.')
