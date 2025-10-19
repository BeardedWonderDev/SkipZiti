import Foundation
import SwiftUI
import SkipZitiServices

public struct SkipZitiDiagnosticsView: View {
    @State private var events: [ZitiClientEvent] = []
    private let client: ZitiClient

    public init(client: ZitiClient) {
        self.client = client
    }

    public var body: some View {
        List {
            ForEach(events.indices, id: \.self) { index in
                Text(description(for: events[index]))
            }
        }
        .task {
            for await event in client.events {
                events.append(event)
            }
        }
        .navigationTitle("SkipZiti Diagnostics")
    }

    private func description(for event: ZitiClientEvent) -> String {
        switch event {
        case .starting:
            return "Runtime starting…"
        case .ready(let services):
            let names = services.map(\.name).joined(separator: ", ")
            return "Ready (\(names))"
        case .identityAdded(let record):
            return "Identity added: \(record.alias)"
        case .identityRemoved(let alias):
            return "Identity removed: \(alias)"
        case .stopped:
            return "Runtime stopped"
        }
    }
}
