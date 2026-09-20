import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: Preferences!
    private var client: PaseoClient!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        let client = PaseoClient(preferences: preferences)
        self.preferences = preferences
        self.client = client
        self.statusItemController = StatusItemController(preferences: preferences, client: client)
        client.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        client?.stop()
    }
}
