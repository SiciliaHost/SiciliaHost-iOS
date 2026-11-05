import Foundation

public let maxFailedStarts = 2
public let startConfirmFrames = 15
private let noStamp: Int64 = -1

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
        let s = store.read()
        let stamp = (s.initPending || s.disabledStamp != 0) ? appStampProvider() : noStamp
        let failed = s.initPending ? s.failedStarts + 1 : s.failedStarts
        let turnOff = failed >= maxFailedStarts
        let allowed = !turnOff && avatarAllowed(isSupported: isSupported, initPending: false, disabledStamp: s.disabledStamp, appStamp: stamp)
        let next = GateState(
            initPending: allowed,
            disabledStamp: disabledStampAfter(initPending: turnOff, disabledStamp: s.disabledStamp, appStamp: stamp),
            failedStarts: turnOff ? 0 : failed
        )
        return store.commit(state: next) && allowed
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
