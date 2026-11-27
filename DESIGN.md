# DESIGN — VietGo (macOS Native Precision)

> Surface Mode: `Operate`
> Reference Systems: Apple Human Interface Guidelines, macOS System Settings, CleanShot X

## 1. Visual Theme & Direction
VietGo's interface follows **macOS Native Precision**: calm translucent window chrome, crisp 1px surface containment, restrained semantic color, and tactile keyboard keycaps. Controls recede so status, shortcuts, and typing state remain scannable within a glance. No decorative gradients, no emoji icons, no clipping grouped forms.

## 2. Color Palette & Semantic Tokens

### Light Mode (macOS System)
- **Window Canvas (`--bg`):** `#F5F5F7` (`NSColor.windowBackgroundColor`)
- **Card Surface (`--surface`):** `#FFFFFF` (`NSColor.controlBackgroundColor`)
- **Elevated Sub-Surface (`--surface-elevated`):** `#FBFBFC`
- **Border Hairline (`--border`):** `rgba(0, 0, 0, 0.08)`
- **Ink Primary (`--text`):** `#1D1D1F` (`Color.primary`)
- **Ink Secondary (`--text-secondary`):** `#6E6E73` (`Color.secondary`)
- **Action Blue (`--accent`):** `#0071E3` (`Color.accentColor`)
- **Success (`--success`):** `#28CD41`
- **Warning (`--warning`):** `#FF9F0A`

### Dark Mode (macOS System)
- **Window Canvas (`--bg`):** `#1C1C1E` (`NSColor.windowBackgroundColor`)
- **Card Surface (`--surface`):** `#262629` (`NSColor.controlBackgroundColor`)
- **Elevated Sub-Surface (`--surface-elevated`):** `#2C2C2E`
- **Border Hairline (`--border`):** `rgba(255, 255, 255, 0.09)`
- **Ink Primary (`--text`):** `#F5F5F7` (`Color.primary`)
- **Ink Secondary (`--text-secondary`):** `#98989D` (`Color.secondary`)
- **Action Blue (`--accent`):** `#0A84FF` (`Color.accentColor`)
- **Success (`--success`):** `#30D158`
- **Warning (`--warning`):** `#FF9F0A`

## 3. Typography Rules
- **UI Font:** `SF Pro Text` / `SF Pro Display` (`-apple-system, BlinkMacSystemFont, sans-serif`)
- **Monospace:** `SF Mono` (`ui-monospace, SFMono-Regular, Menlo, monospace`) strictly for shortcut keycaps and raw keystroke tokens (`tieengs vieetj`, `URRL`, `nhw`)
- **Scale:**
  - Hero status title: `16pt` Semibold
  - Card / section label: `13pt` Medium
  - Setting title: `13pt` Regular/Medium
  - Supporting description: `11.5pt` Regular, `max-width: 62ch`, `Color.secondary`
  - Keycap token: `11.5pt` Semibold (`SF Mono` / Rounded)

## 4. Layout & Geometry
- **Window Frame:** `620 × 520` pt (`VStack(spacing: 0)`) — zero clipped header rows, zero hidden bottom sections.
- **Persistent Status Header:** Animated `40 × 40` squircle monogram (`V` active / `E` English), active configuration summary, Accessibility status pill, and master switch.
- **Tab Bar:** 4 equal-intent segments (`Bộ gõ`, `Thông minh`, `Phím tắt`, `Gõ thử`) using uniform SF Symbols / 1.7px monoline icons.
- **Radius Scale:**
  - `6pt` — 3D shortcut keycaps & inline code pills
  - `8pt` — Buttons, text editor, inputs
  - `10pt` — Segmented tab bar & active pill
  - `12pt` — Grouped setting cards (`VGSurfaceCard`) & option cards (`VGMethodOptionCard`)
  - `14pt` — Top status monogram badge

## 5. Component & Motion Discipline
- **3D Tactile Keycaps (`VGKeycap`):** Soft top highlight, subtle gradient fill, `1.5pt` bottom key skirt (`border-bottom-width: 2px`), tabular numbers/glyphs.
- **Option Cards (`VGMethodOptionCard`):** Side-by-side Telex vs VNI selector showing live keystroke preview, accent ring on selection, checkmark badge.
- **Motion:** SwiftUI `.spring(response: 0.24, dampingFraction: 0.82)` for status badge and tab transitions (`150–240ms`), strictly state-driven.
- **All Required States:** Vietnamese Active (`V`), English Mode (`E`), Accessibility Permission Needed (inline recovery banner), Accessibility Granted, Recording Shortcut (`Đang ghi…`), and Empty/Populated Live Sandbox.
