import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Zen GitHub Update — a rabbit in the bar for your GitHub checkouts.
//
// The widget auto-discovers every top-level git repo under $HOME whose origin
// is on github.com (via the `zen-gh` helper), shows their current version and
// how far behind upstream they are, and lets you update or forget each one.
// Paste a GitHub URL (or owner/repo) to clone and start tracking a new project.
Panel {
  id: root
  moduleName: "github-update"
  ipcTarget: "github-update"
  manageIpc: false

  // The installed plugin's own folder, used to read its manifest version.
  readonly property string pluginId: "github-update"
  readonly property string manifestPath:
    (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + pluginId + "/manifest.json"

  // Installed version, read from the plugin manifest so it always matches the
  // build that is actually installed (a release bump changes manifest.json once).
  property string version: ""

  FileView {
    id: manifestView
    path: root.manifestPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var m = JSON.parse(String(manifestView.text() || "{}"))
        if (m && m.version) root.version = String(m.version)
      } catch (e) {
        root.version = ""
      }
    }
  }

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color updateGreen: "#7bd88f"
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Nerd Font glyphs by codepoint so no raw PUA bytes live in this file.
  readonly property string glyphRabbit: String.fromCodePoint(0xF0907)
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)
  readonly property string glyphDownload: String.fromCodePoint(0xF01DA)
  readonly property string glyphTrash: String.fromCodePoint(0xF0A79)
  readonly property string glyphPlus: String.fromCodePoint(0xF0415)
  readonly property string glyphMagnify: String.fromCodePoint(0xF0349)
  readonly property string glyphGithub: String.fromCodePoint(0xF02A4)
  readonly property string glyphDown: String.fromCodePoint(0x2193)
  readonly property string glyphDefault: String.fromCodePoint(0xF04CE)
  readonly property string glyphLink: String.fromCodePoint(0xF0339)
  readonly property string glyphPlay: String.fromCodePoint(0xF040A)

  property var apps: []
  property bool loading: false
  property string statusText: ""
  property string filterText: ""
  property int selectedIndex: 0
  property bool confirmUninstallOpen: false
  property var pendingUninstall: null

  // The already-installed project the install field would duplicate, if any.
  readonly property var installDuplicate: installedDuplicate(addField.text)

  readonly property int updateCount: {
    var n = 0
    for (var i = 0; i < apps.length; i++) if (Number(apps[i].behind) > 0) n++
    return n
  }

  readonly property var filteredApps: {
    var q = String(filterText).toLowerCase()
    if (q === "") return apps
    var out = []
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i]
      var hay = String(a.name) + " " + String(a.label || "") + " " + String(a.slug) + " " + String(a.path || "")
      if (hay.toLowerCase().indexOf(q) >= 0) out.push(a)
    }
    return out
  }

  function displayName(app) {
    if (!app) return ""
    return app.label && String(app.label) !== "" ? String(app.label) : String(app.name)
  }

  // Is the text in the install field a project that is already installed?
  // Compares the repo name, the full owner/repo slug and the installed slug, so
  // "pen-setup", "owner/pen-setup" and a full URL all hit the same row.
  function installedDuplicate(value) {
    var raw = String(value || "").trim().replace(/\.git$/, "").replace(/\/+$/, "")
    if (raw === "") return null
    var slug = raw.replace(/^.*github\.com[\/:]/, "").replace(/^\/+/, "").toLowerCase()
    var repo = slug.split("/").pop()
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i]
      var name = String(a.name || "").toLowerCase()
      var installed = String(a.slug || "").toLowerCase()
      if (name !== "" && (name === repo || name === slug)) return a
      if (installed !== "" && (installed === slug || installed.split("/").pop() === repo)) return a
    }
    return null
  }

  function shellQuote(value) {
    if (bar && typeof bar.shellQuote === "function") return bar.shellQuote(String(value))
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function refresh(fetch) {
    loading = true
    statusText = ""
    scan.command = fetch
      ? ["zen-gh", "list-json", "--fetch", "--sync-menu", "--sync-launchers"]
      : ["zen-gh", "list-json", "--sync-menu", "--sync-launchers"]
    scan.running = true
  }

  // Left-clicking an app opens its repository on GitHub.
  function openGithub(app) {
    if (!app) return
    var slug = String(app.slug || "")
    if (slug === "") {
      statusText = displayName(app) + " has no GitHub repository"
      return
    }
    Qt.openUrlExternally("https://github.com/" + slug)
  }

  // Launch an app through its launcher entry, or open a plugin's panel.
  function launchApp(app) {
    if (!app) return
    if (bar && typeof bar.run === "function")
      bar.run("zen-gh launch " + shellQuote(app.name))
    statusText = (app.kind === "plugin" ? "Opening " : "Launching ") + displayName(app) + "…"
  }

  function runInTerminal(command) {
    if (bar && typeof bar.run === "function")
      bar.run("omarchy-launch-floating-terminal-with-presentation " + shellQuote(command))
  }

  function installFromInput() {
    var value = String(addField.text).trim()
    if (value === "") return
    var dup = installedDuplicate(value)
    if (dup) {
      statusText = displayName(dup) + " is already installed"
      return
    }
    runInTerminal("zen-gh add " + shellQuote(value))
    addField.text = ""
    statusText = "Cloning " + value + "…"
    close()
  }

  function selectedApp() {
    var list = filteredApps
    if (list.length === 0) return null
    return list[Math.max(0, Math.min(selectedIndex, list.length - 1))]
  }

  function updateApp(app) {
    if (!app) return
    runInTerminal("zen-gh update " + shellQuote(app.name))
    statusText = "Updating " + displayName(app) + "…"
    close()
  }

  // Update every tracked app that is actually behind. `zen-gh update-all`
  // skips checkouts already at their upstream, so up-to-date apps are never
  // pulled or rebuilt.
  function updateAll() {
    if (root.updateCount <= 0) {
      statusText = "Everything is up to date"
      return
    }
    runInTerminal("zen-gh update-all")
    statusText = "Updating " + root.updateCount + " app(s)…"
    close()
  }

  // The trash asks first: open a small in-panel confirm, then remove on OK.
  function requestUninstall(app) {
    if (!app) return
    pendingUninstall = app
    confirmUninstallOpen = true
    confirmDialog.selectedIndex = 0
    confirmDialog.forceActiveFocus()
  }

  function cancelUninstall() {
    confirmUninstallOpen = false
    pendingUninstall = null
    Qt.callLater(function() { if (search) search.forceActiveFocus() })
  }

  function uninstallApp(app) {
    if (!app) return
    runInTerminal("zen-gh uninstall --yes " + shellQuote(app.name))
    statusText = "Uninstalling " + displayName(app) + "…"
    close()
  }

  function confirmUninstall() {
    var app = pendingUninstall
    confirmUninstallOpen = false
    pendingUninstall = null
    uninstallApp(app)
  }

  function moveCursor(dx, dy) {
    var list = filteredApps
    if (list.length === 0) return
    if (dy !== 0) selectedIndex = Math.max(0, Math.min(list.length - 1, selectedIndex + dy))
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    selectedIndex = 0
    refresh(true)
    Qt.callLater(function() { if (search) search.forceActiveFocus() })
  }

  Component.onCompleted: refresh(true)

  Timer {
    id: autoCheck
    interval: 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh(true)
  }

  Process {
    id: scan
    command: ["zen-gh", "list-json"]
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
    }
    onExited: function(code) {
      root.loading = false
      var raw = String(scanOut.text || "[]").trim()
      try {
        var parsed = JSON.parse(raw)
        root.apps = Array.isArray(parsed) ? parsed : []
      } catch (e) {
        root.apps = []
        root.statusText = "Scan failed"
      }
      if (root.selectedIndex >= root.filteredApps.length) root.selectedIndex = 0
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphRabbit
    active: root.updateCount > 0
    activeColor: root.updateGreen
    tooltipText: root.updateCount > 0
      ? "GitHub apps · " + root.updateCount + " to update"
      : "GitHub apps"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.refresh(true)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: search
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmUninstallOpen || search.activeFocus || addField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.updateApp(root.selectedApp())
      onDeleteRequested: root.requestUninstall(root.selectedApp())
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.spacing.md

          // ------------------------------------------------------------- header
          Item {
            width: parent.width
            implicitHeight: Math.max(headerLeft.implicitHeight, headerActions.implicitHeight)

            Row {
              id: headerLeft
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Text {
                text: root.glyphGithub
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                  text: "GitHub Update"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  text: root.loading
                    ? "Scanning…"
                    : (root.version !== "" ? "v" + root.version + " · " : "")
                      + (root.apps.length + " tracked · " + root.updateCount + " to update")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Button {
                id: updateAllButton
                text: "Update all"
                iconText: root.glyphDownload
                tooltipText: root.updateCount > 0
                  ? "Update all " + root.updateCount + " app(s) that are behind"
                  : "Everything is up to date"
                foreground: root.updateCount > 0 ? root.updateGreen : root.foreground
                accent: root.updateGreen
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                enabled: root.updateCount > 0 && !root.loading
                onClicked: root.updateAll()
              }

              PanelActionButton {
                id: refreshButton
                iconText: root.glyphRefresh
                tooltipText: root.updateCount > 0
                  ? root.updateCount + " update(s) available — click to check again (online)"
                  : "Check for updates (online fetch)"
                foreground: root.updateCount > 0 ? root.accent : root.foreground
                fontFamily: root.fontFamily
                enabled: !root.loading
                onClicked: root.refresh(true)
              }
            }
          }

          // -------------------------------------------------------------- search
          TextField {
            id: search
            width: parent.width
            placeholderText: "Search apps"
            foreground: root.foreground
            accent: root.accent
            onTextChanged: { root.filterText = text; root.selectedIndex = 0 }
            Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
            Keys.onDownPressed: function(event) { root.moveCursor(0, 1); event.accepted = true }
            Keys.onUpPressed: function(event) { root.moveCursor(0, -1); event.accepted = true }
            Keys.onReturnPressed: function(event) { root.updateApp(root.selectedApp()); event.accepted = true }
          }

          // --------------------------------------------------------------- add
          Row {
            width: parent.width
            spacing: Style.spacing.sm

            TextField {
              id: addField
              width: parent.width - installButton.width - parent.spacing
              placeholderText: root.installDuplicate
                ? root.displayName(root.installDuplicate) + " is already installed"
                : "Paste a GitHub URL or owner/repo to install"
              foreground: root.foreground
              accent: root.accent
              Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
              Keys.onReturnPressed: function(event) { root.installFromInput(); event.accepted = true }
            }

            Button {
              id: installButton
              text: root.installDuplicate ? "Installed" : "Install"
              iconText: root.glyphPlus
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              enabled: !root.installDuplicate
              onClicked: root.installFromInput()
            }
          }

          PanelSeparator { width: parent.width }

          // -------------------------------------------------------------- list
          Column {
            width: parent.width
            spacing: Style.spacing.xs

            PanelSectionHeader {
              text: root.filterText === "" ? "INSTALLED" : "RESULTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !root.loading && root.filteredApps.length === 0
              width: parent.width
              text: root.apps.length === 0
                ? "No GitHub checkouts found under $HOME."
                : "No apps match “" + root.filterText + "”."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.filteredApps

              delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: rowContent.implicitHeight + Style.spacing.lg * 2

                readonly property bool selected: index === root.selectedIndex
                readonly property int behind: Number(modelData.behind) > 0 ? Number(modelData.behind) : 0
                readonly property bool linked: modelData.linked === true
                readonly property bool launchable: String(modelData.launch || "") !== ""
                readonly property string sourcePath: String(modelData.path || "").replace(/^\/home\/[^\/]+/, "~")
                readonly property var defaults: modelData.defaults || []
                // Declared version from the app's manifest, with the checked-out
                // commit beside it; falls back to the git describe/commit.
                readonly property string versionLabel: {
                  var manifest = String(modelData.manifest || "")
                  var commit = String(modelData.commit || "")
                  var version = String(modelData.version || "")
                  if (manifest !== "") return commit !== "" ? manifest + " · " + commit : manifest
                  return version || commit
                }

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: row.selected
                    ? Style.selectedFillFor(root.foreground, root.accent)
                    : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    root.selectedIndex = row.index
                    if (mouse.button === Qt.RightButton) root.updateApp(row.modelData)
                    else root.openGithub(row.modelData)
                  }
                }

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.sm
                  anchors.rightMargin: Style.spacing.sm
                  spacing: Style.spacing.sm

                  PanelActionButton {
                    id: playButton
                    iconText: root.glyphPlay
                    tooltipText: row.launchable
                      ? (row.modelData.kind === "plugin" ? "Open " : "Launch ") + root.displayName(row.modelData)
                      : "No launcher entry for " + root.displayName(row.modelData) + " yet"
                    foreground: root.foreground
                    hoverColor: root.accent
                    fontFamily: root.fontFamily
                    enabled: row.launchable
                    onClicked: { root.selectedIndex = row.index; root.launchApp(row.modelData) }
                  }

                  Column {
                    width: Math.max(0, parent.width - playButton.width - badges.width - rowActions.width - parent.spacing * 3)
                    spacing: Style.spacing.xxs

                    Text {
                      width: parent.width
                      text: root.displayName(row.modelData)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: (row.modelData.kind === "plugin" ? "plugin" : "app")
                        + (row.modelData.slug && row.modelData.slug !== "" ? " · " + row.modelData.slug : "")
                        + (row.versionLabel !== "" ? " · " + row.versionLabel : "")
                        + (row.linked ? " · " + row.sourcePath : "")
                        + (row.modelData.branch && row.modelData.branch !== "?" ? " · " + row.modelData.branch : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Row {
                    id: badges
                    spacing: Style.spacing.xs
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      visible: row.defaults.length > 0
                      text: root.glyphDefault
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.spacing.xxs
                        hoverEnabled: true
                        ToolTip.visible: containsMouse
                        ToolTip.text: "Default in Omarchy:\n" + row.defaults.join("\n")
                      }
                    }

                    Text {
                      visible: row.linked
                      text: root.glyphLink
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.spacing.xxs
                        hoverEnabled: true
                        ToolTip.visible: containsMouse
                        ToolTip.text: "Updates reinstall from:\n" + row.sourcePath
                      }
                    }

                    Rectangle {
                      visible: row.behind > 0
                      radius: Style.cornerRadius
                      color: Style.selectedFillFor(root.foreground, root.accent)
                      implicitWidth: badgeText.implicitWidth + Style.spacing.sm * 2
                      implicitHeight: badgeText.implicitHeight + Style.spacing.xxs * 2

                      Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.glyphDown + row.behind
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Text {
                      visible: row.behind === 0
                      text: "✓"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Row {
                    id: rowActions
                    spacing: Style.spacing.xxs
                    anchors.verticalCenter: parent.verticalCenter

                    PanelActionButton {
                      iconText: root.glyphGithub
                      tooltipText: "Open " + (row.modelData.slug ? row.modelData.slug : root.displayName(row.modelData)) + " on GitHub"
                      foreground: root.foreground
                      hoverColor: root.accent
                      fontFamily: root.fontFamily
                      onClicked: { root.selectedIndex = row.index; root.openGithub(row.modelData) }
                    }

                    PanelActionButton {
                      iconText: root.glyphDownload
                      tooltipText: row.behind > 0
                        ? "Update " + row.modelData.name + " (" + row.behind + " behind)"
                        : (row.linked
                          ? "Reinstall " + root.displayName(row.modelData) + " from " + row.sourcePath
                          : row.modelData.name + " is up to date")
                      foreground: row.behind > 0 ? root.updateGreen : root.foreground
                      hoverColor: row.behind > 0 ? root.updateGreen : root.foreground
                      fontFamily: root.fontFamily
                      enabled: (row.behind > 0 || row.linked) && !root.loading
                      onClicked: { root.selectedIndex = row.index; root.updateApp(row.modelData) }
                    }

                    PanelActionButton {
                      iconText: root.glyphTrash
                      tooltipText: "Uninstall " + root.displayName(row.modelData) + " (removes its files, Omarchy defaults & its menu row)"
                      foreground: root.foreground
                      hoverColor: root.urgent
                      fontFamily: root.fontFamily
                      onClicked: { root.selectedIndex = row.index; root.requestUninstall(row.modelData) }
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.statusText !== ""
            width: parent.width
            text: root.statusText
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "▶ launch · Enter update · X uninstall · click opens GitHub · right-click updates"
            color: Qt.darker(root.foreground, 2.0)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        opened: root.confirmUninstallOpen
        focus: root.confirmUninstallOpen
        message: root.pendingUninstall
          ? "Uninstall " + root.displayName(root.pendingUninstall) + "?\nIts files, Omarchy defaults and menu row are removed."
          : ""
        cancelText: "Cancel"
        confirmText: "Uninstall"
        background: Color.background
        foreground: root.foreground
        selectedText: root.accent
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.cancelUninstall()
        onConfirmed: root.confirmUninstall()
        Keys.onPressed: function(event) {
          if (confirmDialog.handleKey(event)) event.accepted = true
        }
      }
    }
  }
}
