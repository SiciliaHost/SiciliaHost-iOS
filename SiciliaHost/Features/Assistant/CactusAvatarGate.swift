import Foundation

public let maxFailedStarts = 2
public let startConfirmFrames = 15

public func avatarAllowed(isSupported: Bool, initPending: Bool, disabledStamp: Int64, appStamp: Int64) -> Bool {
    return isSupported && !initPending && disabledStamp != appStamp
}

public func disabledStampAfter(initPending: Bool, disabledStamp: Int64, appStamp: Int64) -> Int64 {
    return initPending ? appStamp : disabledStamp
}

public func startConfirmed(framesDrawn: Int, animated: Bool) -> Bool {
    return framesDrawn >= 1 && (framesDrawn >= startConfirmFrames || !animated)
}

public struct GateState: Equatable, Sendable {
    public let initPending: Bool
    public let disabledStamp: Int64
    public let failedStarts: Int

    public init(initPending: Bool, disabledStamp: Int64, failedStarts: Int) {
        self.initPending = initPending
        self.disabledStamp = disabledStamp
        self.failedStarts = failedStarts
    }
}

public protocol GateStore: Sendable {
    func read() -> GateState
    func commit(state: GateState) -> Bool
}

public final class InMemoryGateStore: GateStore, @unchecked Sendable {
    private var state: GateState

    public init(initial: GateState = GateState(initPending: false, disabledStamp: 0, failedStarts: 0)) {
        self.state = initial
    }

    public func read() -> GateState {
        return state
    }

    public func commit(state: GateState) -> Bool {
        self.state = state
        return true
    }
}

public final class AvatarGate: @unchecked Sendable {
    private let store: GateStore
    private let appStampProvider: () -> Int64
    private let isSupported: Bool

    public init(
        store: GateStore = InMemoryGateStore(),
        isSupported: Bool = true,
        appStampProvider: @escaping () -> Int64 = { 1 }
    ) {
        self.store = store
        self.isSupported = isSupported
        self.appStampProvider = appStampProvider
    }

    public func begin() -> Bool {
        let current = store.read()
        let appStamp = appStampProvider()

        if current.initPending {
            let failed = current.failedStarts + 1
            let disabled = failed >= maxFailedStarts ? appStamp : current.disabledStamp
            _ = store.commit(state: GateState(initPending: false, disabledStamp: disabled, failedStarts: failed))
            return false
        }

        guard avatarAllowed(isSupported: isSupported, initPending: false, disabledStamp: current.disabledStamp, appStamp: appStamp) else {
            return false
        }

        // Segna avvio in corso
        return store.commit(state: GateState(initPending: true, disabledStamp: current.disabledStamp, failedStarts: current.failedStarts))
    }

    public func initFinished() {
        let current = store.read()
        _ = store.commit(state: GateState(initPending: false, disabledStamp: current.disabledStamp, failedStarts: 0))
    }

    public func released() {
        let current = store.read()
        if current.initPending {
            _ = store.commit(state: GateState(initPending: false, disabledStamp: current.disabledStamp, failedStarts: current.failedStarts))
        }
    }
}
