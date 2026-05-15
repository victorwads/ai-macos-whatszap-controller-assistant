import Foundation

extension AppModel {
    private var serverCallsInMemoryLimit: Int { 2_000 }

    func appendServerCall(_ entry: MCPServerCallEntry) {
        serverCalls.append(entry)

        if serverCalls.count > serverCallsInMemoryLimit {
            serverCalls.removeFirst(serverCalls.count - serverCallsInMemoryLimit)
        }

        Task {
            await serverCallsRepository.append(entry)
        }
    }

    func clearServerCalls() {
        serverCalls.removeAll()
        Task {
            await serverCallsRepository.clear()
        }
    }

    func loadPersistedServerCalls() async {
        let loaded = await serverCallsRepository.loadAll()
        serverCalls = Array(loaded.suffix(serverCallsInMemoryLimit))
    }
}
