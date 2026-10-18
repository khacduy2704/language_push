enum AppTab: Int, CaseIterable, Identifiable {
    case world
    case pushList
    case search
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .world: return "World"
        case .pushList: return "List word to push"
        case .search: return "Search"
        case .settings: return "Setting"
        }
    }

    var symbol: String {
        switch self {
        case .world: return "globe"
        case .pushList: return "bell"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }

    var migrationMessage: String {
        switch self {
        case .world:
            return "Home-screen widgets and Flutter data import have not been migrated yet."
        case .pushList:
            return "Listening exercises and home-screen widgets have not been migrated yet."
        case .search:
            return "Pronunciation recordings and Flutter data import have not been migrated yet."
        case .settings:
            return "Cached audio and authentication have not been migrated yet."
        }
    }
}
