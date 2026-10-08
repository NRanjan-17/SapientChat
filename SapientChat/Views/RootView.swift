import SwiftUI

/// The app's four sections as tabs. The selected tab is kept per scene.
struct RootView: View {
    @Bindable var viewModel: ChatListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("selectedTab") private var storedTab = AppTab.chats

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            Tab(AppTab.chats.title, systemImage: AppTab.chats.symbol, value: .chats) {
                ChatsTab(viewModel: viewModel)
            }
            Tab(AppTab.models.title, systemImage: AppTab.models.symbol, value: .models) {
                ModelManagerView(viewModel: viewModel.models)
            }
            Tab(AppTab.benchmark.title, systemImage: AppTab.benchmark.symbol, value: .benchmark) {
                BenchmarkTab(benchmark: viewModel.benchmark, compare: viewModel.compare, makeSelector: viewModel.makeModelSelector)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: .settings) {
                SettingsTab(server: viewModel.server) {
                    Task { await viewModel.models.unloadAll() }
                }
            }
        }
        // The sections always sit in the tab bar: across the top on iPad,
        // at the bottom on iPhone (no sidebar).
        .tabViewStyle(.tabBarOnly)
        // An overlay, not a safe-area inset: an inset on the TabView pushes
        // every tab's navigation bar down even while the banner is empty.
        .overlay(alignment: .top) {
            HandoffBanner(viewModel: viewModel.handoff)
        }
        .onOpenURL { url in
            if HandoffViewModel.handles(url) { viewModel.handoff.open(url) }
        }
        .task { await viewModel.device.observeThermal() }
        .onAppear(perform: restoreTab)
        .onChange(of: viewModel.selectedTab) { _, tab in
            storedTab = tab
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
    }

    private func restoreTab() {
        viewModel.selectedTab = storedTab
        #if DEBUG
        // Screenshots and UI checks: `-SapientTab benchmark` opens that tab.
        if let name = UserDefaults.standard.string(forKey: "SapientTab"), let tab = AppTab(rawValue: name) {
            viewModel.selectedTab = tab
        }
        #endif
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            viewModel.appDidBecomeActive()
            viewModel.server.appDidBecomeActive()
        } else {
            viewModel.appDidLeaveForeground()
            viewModel.server.appDidLeaveForeground()
        }
    }
}

#Preview {
    RootView(viewModel: .preview)
}
