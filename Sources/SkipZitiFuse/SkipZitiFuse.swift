import Foundation
import SkipFuse
import SkipZitiServices

public enum SkipZitiFuseBridge {
    public static func configure() {
        _ = SkipFuseVersion.current
    }

    public static func expose(
        client: ZitiClient,
        register handler: (String, @escaping () -> Void) -> Void
    ) {
        handler("skipZiti.shutdown") {
            Task {
                await client.shutdown()
            }
        }
    }
}

private enum SkipFuseVersion {
    static var current: String {
        "embedded"
    }
}
