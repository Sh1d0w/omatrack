# Bar widget

`BarWidget.qml` — the `bar-widget` kind, installed in the **right** section
(`defaultSection: "right"`, enabled with
`omarchy plugin enable io.github.sh1d0w.timetrack --section right`). It is
the live label for the current task and the host for the quick-start popup.

## Display

The label is a single binding that re-evaluates only when its inputs change
(service map, running state, and the 1s `elapsedLabel` while running):

| State     | Label                                              | Style |
|-----------|----------------------------------------------------|-------|
| idle      | `▶` (U+25B6)                                       | muted |
| running   | the entry's description if set, else the client name (or `-`), then two spaces + `HH:MM:SS` | `Color.accent` |

The running client name resolves through the service's `clientName()`; if it
cannot resolve (data edited away out from under a running timer) the label
falls back to `-`.

The tooltip (`tooltipText`) carries the detail the bar label can't:

- running: `Acme — Hero section · 01:02:03 · billable` (or `non-billable`)
- idle with time logged today: `Today 04:12 · start a task`
- idle, empty day: `No active timer`

## Service access

The bar widget is a host-injected object: the shell gives it `bar`,
`moduleName`, and `settings`. The headless engine is reached through:

```qml
readonly property var service:
    bar ? bar.shell.serviceFor("io.github.sh1d0w.timetrack") : null
```

This binding re-evaluates when the shell reassigns its `_services` map, so
the widget attaches automatically on shell startup even though the bar widget
is constructed before the plugin's service finishes loading.

## Popup shape contract

The popup is a `Loader` on `Popup.qml`. The shell's summon routing inspects
the bar-widget root for the `opened`/`open`/`close` shape; the widget
implements it (`popupLoader.item.opened === true`, `open()`/`close()`
delegating to the loaded popup) and uses `popoutSwitchClosing` /
`closeForPopoutSwitch` so the bar treats the popup as its popout identity.

## Interaction

- **Left click** → `togglePanel()` (open/close the anchored popup; Esc and
  focus-out close it).
- **Right click / middle click** → ignored by design (no context menu).
- The popup itself — contents, anchoring, behavior — is documented in
  [popup.md](popup.md).

## Contingency: idle glyph

The idle label uses the geometric glyph `▶`. If the bar font renders it as
tofu, switch the idle label to the text `idle` (one-line change in the
`label` binding) and re-verify with `omarchy capture screenshot`.
