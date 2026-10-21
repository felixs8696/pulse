import Foundation

/// Each source owns a scanner and serial queue. A slow source cannot block others,
/// and refresh never starts a second scan for a source that's already busy.
public final class SessionScanCoordinator: @unchecked Sendable {
    public enum Event: Sendable {
        case started(Provider)
        case slow(Provider)
        case finished(ScanResult)
    }
    private let lock = NSLock()
    private var busy: Set<Provider> = []
    private let workers: [Provider: DispatchQueue]
    private let scan: @Sendable (Provider, Set<String>) -> ScanResult
    private let slowAfter: TimeInterval

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, slowAfter: TimeInterval = 12,
                scan: (@Sendable (Provider, Set<String>) -> ScanResult)? = nil) {
        workers = Dictionary(uniqueKeysWithValues: Provider.allCases.map {
            ($0, DispatchQueue(label: "pulse.scan.\($0.rawValue)", qos: .utility))
        })
        let scanners = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, SessionScanner(home: home)) })
        self.scan = scan ?? { provider, pins in scanners[provider]!.scan(provider: provider, pinnedIDs: pins) }
        self.slowAfter = slowAfter
    }

    public func refresh(pinnedIDs: Set<String> = [], receive: @escaping @Sendable (Event) -> Void) {
        for provider in Provider.allCases {
            lock.lock()
            let started = busy.insert(provider).inserted
            lock.unlock()
            guard started else { continue }
            receive(.started(provider))
            // A separate queue reports delays even if the scanner is blocked in I/O.
            let watchdog = DispatchWorkItem { receive(.slow(provider)) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + slowAfter, execute: watchdog)
            workers[provider]!.async { [self] in
                let start = Date()
                let result = scan(provider, pinnedIDs)
                watchdog.cancel()
                NSLog("Pulse %@ scan finished in %.2fs (%d chats)", provider.rawValue, Date().timeIntervalSince(start), result.sessions.count)
                // Deliver the result before allowing a later refresh to overtake it.
                receive(.finished(result))
                lock.lock()
                busy.remove(provider)
                lock.unlock()
            }
        }
    }
}
