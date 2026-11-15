class_name UITheme
extends Object
## Shared dark/orange industrial UI theme.

const ACCENT := Color("e8772e")
const TEXT := Color(0.92, 0.92, 0.9)
const MUTED := Color(0.62, 0.64, 0.66)
const GOOD := Color("5fd38a")
const BAD := Color("e05a4a")


static func make() -> Theme:
    var t := Theme.new()
    t.default_font_size = 16
    t.set_stylebox("panel", "PanelContainer", box(Color(0.06, 0.07, 0.09, 0.88), Color(1, 1, 1, 0.07), 1, 6))
    t.set_stylebox("normal", "Button", box(Color(0.15, 0.17, 0.2), Color(1, 1, 1, 0.05), 1, 4))
    t.set_stylebox("hover", "Button", box(Color(0.22, 0.24, 0.28), ACCENT, 2, 4))
    t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.25), ACCENT, 2, 4))
    t.set_stylebox("hover_pressed", "Button", box(ACCENT.darkened(0.15), ACCENT, 2, 4))
    t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.11), Color(0, 0, 0, 0), 0, 4))
    t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    t.set_color("font_color", "Button", TEXT)
    t.set_color("font_hover_color", "Button", Color.WHITE)
    t.set_color("font_pressed_color", "Button", Color.WHITE)
    t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
    t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.42))
    t.set_color("font_color", "Label", TEXT)
    t.set_stylebox("background", "ProgressBar", box(Color(0.12, 0.13, 0.15), Color(0, 0, 0, 0), 0, 3, 0))
    t.set_stylebox("fill", "ProgressBar", box(GOOD, Color(0, 0, 0, 0), 0, 3, 0))
    t.set_color("separator", "HSeparator", Color(1, 1, 1, 0.08))
    return t


static func box(bg: Color, border: Color, width: int, radius: int, margin: int = 10) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(radius)
    s.content_margin_left = margin
    s.content_margin_right = margin
    s.content_margin_top = margin * 0.6
    s.content_margin_bottom = margin * 0.6
    return s
