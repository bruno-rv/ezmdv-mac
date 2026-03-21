import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCommandPalette = false
    @State private var showGraph = false
    @State private var isGraphMinimized = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                if !appState.tabs.isEmpty {
                    TabBarView()
                }
                DetailContentView()
                StatusBar()
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        .onAppear {
            NSApp.appearance = NSAppearance(named: appState.isDarkMode ? .darkAqua : .aqua)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKnowledgeGraph)) { _ in
            showGraph.toggle()
        }
        .overlay {
            if showGraph, let tab = appState.primaryTab {
                if isGraphMinimized {
                    VStack {
                        Spacer()
                        GraphView(isPresented: $showGraph, projectId: tab.projectId, isMinimized: $isGraphMinimized)
                            .frame(maxWidth: .infinity)
                    }
                    .transition(.opacity)
                } else {
                    GraphView(isPresented: $showGraph, projectId: tab.projectId, isMinimized: $isGraphMinimized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: showGraph)
        .animation(.easeInOut(duration: 0.25), value: isGraphMinimized)
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    VStack {
                        CommandPalette(isPresented: $showCommandPalette)
                            .padding(.top, 60)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
    }
}

struct DetailContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.splitView {
            SplitContentView()
        } else if let tab = appState.primaryTab {
            MarkdownPaneView(pane: .primary, tab: tab, splitContext: false)
        } else {
            EmptyStateView()
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a file to view")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open a folder with ⌘O or select a file from the sidebar")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
