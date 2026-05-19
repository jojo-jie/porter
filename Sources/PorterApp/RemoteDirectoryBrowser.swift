import SwiftUI

struct RemoteDirectoryBrowserContainer: View {
    @Binding var path: String
    @StateObject private var browser: RemoteDirectoryBrowserModel
    let onDismiss: () -> Void

    init(hostAlias: String, path: Binding<String>, onDismiss: @escaping () -> Void) {
        _path = path
        _browser = StateObject(wrappedValue: RemoteDirectoryBrowserModel(hostAlias: hostAlias, initialPath: path.wrappedValue))
        self.onDismiss = onDismiss
    }

    var body: some View {
        RemoteDirectoryBrowserSheet(browser: browser, boundPath: $path, onDismiss: onDismiss)
    }
}
