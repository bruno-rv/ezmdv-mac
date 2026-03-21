import SwiftUI

@main
struct EzmdvApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.loadState()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    appState.showOpenFolderDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(name: .saveCurrentFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("New File") {
                    createFileInFocusedProject()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder") {
                    createFolderInFocusedProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Close Tab") {
                    closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Export
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export as HTML...") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // Edit menu
            CommandMenu("Edit") {
                Button("Toggle Edit Mode") {
                    NotificationCenter.default.post(name: .toggleEditMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Live Preview") {
                    NotificationCenter.default.post(name: .togglePreviewMode, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            // View menu
            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()

                Button("Split View") {
                    appState.toggleSplitView()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Toggle Dark Mode") {
                    appState.toggleTheme()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            // Help menu — About
            CommandGroup(replacing: .appInfo) {
                Button("About ezmdv") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
            }

            // Navigate menu
            CommandMenu("Navigate") {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Knowledge Graph") {
                    NotificationCenter.default.post(name: .showKnowledgeGraph, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("Next Tab") {
                    navigateTab(forward: true)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Previous Tab") {
                    navigateTab(forward: false)
                }
                .keyboardShortcut("[", modifiers: .command)
            }
        }
    }

    // MARK: - Helpers

    private func createFileInFocusedProject() {
        // Post notification — SidebarView's ProjectListView will handle showing the inline field
        NotificationCenter.default.post(name: .createFileInFocusedProject, object: nil)
    }

    private func createFolderInFocusedProject() {
        NotificationCenter.default.post(name: .createFolderInFocusedProject, object: nil)
    }

    private func closeCurrentTab() {
        let tab = appState.focusedPane == .secondary
            ? appState.secondaryTab : appState.primaryTab
        if let tab = tab {
            appState.closeTab(tab)
        }
    }

    private func navigateTab(forward: Bool) {
        guard !appState.tabs.isEmpty else { return }
        let currentTab = appState.focusedPane == .secondary
            ? appState.secondaryTab : appState.primaryTab
        guard let current = currentTab,
              let idx = appState.tabs.firstIndex(of: current) else { return }
        let nextIdx = forward
            ? (idx + 1) % appState.tabs.count
            : (idx - 1 + appState.tabs.count) % appState.tabs.count
        let next = appState.tabs[nextIdx]
        appState.openFile(projectId: next.projectId, filePath: next.filePath)
    }
}

extension Notification.Name {
    static let createFileInFocusedProject = Notification.Name("createFileInFocusedProject")
    static let createFolderInFocusedProject = Notification.Name("createFolderInFocusedProject")
    static let toggleEditMode = Notification.Name("toggleEditMode")
    static let togglePreviewMode = Notification.Name("togglePreviewMode")
    static let saveCurrentFile = Notification.Name("saveCurrentFile")
    static let showCommandPalette = Notification.Name("showCommandPalette")
    static let showKnowledgeGraph = Notification.Name("showKnowledgeGraph")
    static let exportHTML = Notification.Name("exportHTML")
    static let showAbout = Notification.Name("showAbout")
}
