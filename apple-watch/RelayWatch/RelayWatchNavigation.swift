import Foundation

enum RelayWatchRoute: Hashable {
    case approval(String)
    case question(String)
    case tasks
    case task(String)
    case activity(String)
    case instruction(String?)
    case newTask
    case voice
    case more
    case history
    case settings
    case identity
    case about
}
