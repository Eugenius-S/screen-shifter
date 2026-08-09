---
name: Screen Shifter
description: A quiet native macOS utility for recording and restoring display scaling.
typography:
  body:
    fontFamily: "System"
  label-mono:
    fontFamily: "System Monospaced"
rounded: {}
spacing: {}
components: {}
---

# Design System: Screen Shifter

## 1. Overview

**Creative North Star: "The Connection Dispatcher"**

Screen Shifter is a background macOS utility, not a destination app. Its interface should feel like a dependable dispatcher: show the current display state, expose the next safe action, and then get out of the way. The visual system is intentionally platform-owned, using SwiftUI's native controls and semantic system appearance instead of a product-specific skin.

The interface should remain predictable after setup. It must not demand attention through decorative surfaces, repeated prompts, or dashboard-like density. Depth comes from native grouped sections and disclosure states, while state changes are expressed through familiar labels, SF Symbols, and semantic colors.

**Key Characteristics:**
- Native macOS appearance
- Quiet, precise state communication
- Grouped settings with progressive disclosure
- System-owned colors and typography
- No browser-specific or custom visual token layer

## 2. Colors

No project-owned color values are defined in the source. SwiftUI's system appearance is the source of truth, so colors adapt to the user's macOS appearance and accessibility settings.

### Primary
- **System accent:** The platform accent is reserved for native control emphasis and active interaction states. The app does not define a custom primary color.

### Neutral
- **System surface:** Native window, Form, and grouped-section surfaces are provided by macOS.
- **Secondary label:** `.secondary` is used for supporting status text, active-display labels, and explanatory copy.
- **System error:** `.red` is used only for the Error section and error messages.

### Named Rules
**The Platform Color Rule.** Do not introduce a product-owned palette when the existing SwiftUI system appearance already expresses the required states.

## 3. Typography

**Display Font:** None. The app has no display or marketing surface.
**Body Font:** System UI, provided by SwiftUI.
**Label/Mono Font:** System monospaced, used for the local log viewer.

**Character:** Typography is quiet and functional. Hierarchy comes from native control roles and small semantic distinctions rather than custom type scale or decorative display treatment.

### Hierarchy
- **Title:** System UI, native control sizing: Window titles, section labels, and display names.
- **Body:** System UI, native control sizing: Picker labels, buttons, toggles, and supporting settings text.
- **Supporting text:** `.footnote` with `.secondary`: Capture status and explanatory power-setting copy.
- **Status label:** `.caption` with `.secondary`: Active-display marker.
- **Log text:** `.caption` in the system monospaced design: Local log content.

### Named Rules
**The Native Type Rule.** Use SwiftUI system typography for controls and labels. Use monospaced system typography only where users inspect log text.

## 4. Elevation

The system is flat by default. The app defines no shadows, gradients, custom borders, or decorative overlays. Depth is conveyed through the native grouped Form treatment, section boundaries, DisclosureGroup expansion, and standard macOS window chrome.

### Named Rules
**The Flat System Rule.** Never add decorative elevation to a background utility. A new layer must communicate grouping, state, or an actionable boundary.

## 5. Components

The component language is native, compact, and state-forward. Controls should remain recognizable as macOS controls and should not be restyled for personality.

### Buttons
- **Shape:** Native SwiftUI Button shape and sizing.
- **Primary:** Standard macOS button treatment for capture, navigation, log, update, and quit actions.
- **Destructive:** Use the native destructive role for `Reset default` and confirmation actions.
- **Hover / Focus:** Owned by the platform's native control appearance.

### Cards / Containers
- **Corner Style:** No custom card radius.
- **Background:** Native grouped Form and window surfaces.
- **Shadow Strategy:** No project-owned shadows.
- **Border:** Native section separation only.
- **Internal Padding:** Native Form spacing, with the Settings surface constrained to 420 points wide.

### Inputs / Fields
- **Style:** Native Picker, Toggle, and TextEditor controls.
- **Focus:** Platform-managed focus treatment.
- **Error / Disabled:** Native disabled appearance; error copy uses the system red semantic color.

### Navigation
- **Style:** A minimal `MenuBarExtra` exposes Settings and Quit. Settings opens a persistent native window with grouped sections.
- **State:** Display-specific content uses DisclosureGroup expansion, status labels, and disabled actions to communicate readiness.

### Display Capture Section
Each display is represented by a reusable native DisclosureGroup containing capture status, configuration navigation actions, completion, and reset. Its active-display marker uses the SF Symbol `checkmark.circle.fill`; saved-profile state uses `checkmark.circle` and missing-profile state uses `circle.dashed`.

## 6. Do's and Don'ts

### Do:
- **Do** use native SwiftUI controls and macOS system appearance as the visual source of truth.
- **Do** use `.secondary` for supporting status and explanation text.
- **Do** use the system red semantic color only for errors and destructive meaning.
- **Do** use SF Symbols when a status or menu action needs an icon.
- **Do** keep the interface quiet, precise, and predictable after setup.
- **Do** preserve grouped settings and progressive disclosure for display-specific details.

### Don't:
- **Don't** add attention-demanding UI after setup.
- **Don't** introduce repeated prompts or dashboard-like complexity into this background utility.
- **Don't** invent a custom palette, display font, shadow system, or decorative surface layer without a new product decision.
- **Don't** replace familiar macOS controls with custom affordances.
- **Don't** use color as decoration or apply the system error color outside error and destructive states.
