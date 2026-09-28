// Source-list navigation, a focused worktree table, and an evidence inspector.
import SwiftUI
import BurroCore

struct ContentView: View {
    @Bindable var store: AppStore
    var notch: NotchController
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: Layout.sidebar, max: 260)
        } content: {
            Group {
                if store.filter == .remote { RemoteSessionsView(store: store) }
                else { WorktreeListView(store: store) }
            }.navigationSplitViewColumnWidth(min: 440, ideal: 650)
        } detail: {
            if store.filter == .remote {
                RemoteSessionDetailView(store: store)
            } else if let tree = store.selected {
                WorktreeDetailView(store: store, tree: tree)
            } else {
                ContentUnavailableView("Select a worktree", systemImage: "arrow.triangle.branch", description: Text("Agent activity and cleanup checks appear here."))
            }
        }
        .navigationTitle("Burro")
        .navigationSubtitle("Worktrees & agents")
        .searchable(text: $store.search, placement: .toolbar, prompt: "Branch, repository, or agent")
        .toolbar {
            ToolbarItemGroup {
                Button { notch.show() } label: { Label("Agent notch", systemImage: "rectangle.topthird.inset.filled") }
                    .help("Show agent notch (⇧⌘B)")
                if store.scanning { ProgressView().controlSize(.small).accessibilityLabel("Refreshing worktrees") }
                Button { Task { await store.refreshRemotes(); await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh worktrees (⌘R)").disabled(store.scanning)
                Button { store.addRepository() } label: { Label("Add repository", systemImage: "folder.badge.plus") }
                    .help("Add a repository")
            }
        }
        .frame(minWidth: 1000, minHeight: 590)
        .onChange(of: store.filter) { _, _ in
            if !store.visibleWorktrees.contains(where: { $0.id == store.selection }) {
                store.selection = store.visibleWorktrees.first?.id
            }
        }
    }
}
