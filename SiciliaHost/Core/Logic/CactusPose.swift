import Foundation

public let bounceCycleS: Float = 0.42
public let bounceStagger: Float = 0.33
public let bounceRise: Float = 0.55
public let landSquashY: Float = 0.18
public let landWidenX: Float = 0.12

public struct FruitPose: Equatable, Sendable {
    public let dy: Float
    public let sx: Float
    public let sy: Float

    public static let rest = FruitPose(dy: 0, sx: 1, sy: 1)

    public init(dy: Float, sx: Float, sy: Float) {
        self.dy = dy
        self.sx = sx
        self.sy = sy
    }
}

public struct EyeScale: Equatable, Sendable {
    public let sx: Float
    public let sy: Float

    public init(sx: Float, sy: Float) {
        self.sx = sx
        self.sy = sy
    }
}

public struct EffectivePose: Equatable, Sendable {
    public let state: CactusState
    public let timeS: Float

    public init(state: CactusState, timeS: Float) {
        self.state = state
        self.timeS = timeS
    }
}

private let twoPi: Float = Float(2.0 * Double.pi)

private func frac(_ x: Float) -> Float {
    return x - floor(x)
}

/// Il rimbalzo del frutto `index` (0-2) al tempo `t`. Fuori da `thinking` i frutti sono a riposo.
public func fruitPose(state: CactusState, t: Float, index: Int) -> FruitPose {
    guard state == .thinking else { return .rest }
    let u = frac(t / bounceCycleS - Float(index) * bounceStagger)
    let hop: Float = u < 0.5 ? sin(u * twoPi) : 0.0
    let land: Float = (u >= 0.5 && u <= 0.62) ? sin((u - 0.5) / 0.12 * Float.pi) : 0.0

    return FruitPose(
        dy: hop * bounceRise,
        sx: 1.0 - hop * 0.06 + land * landWidenX,
        sy: 1.0 + hop * 0.12 - land * landSquashY
    )
}

private func blink(_ t: Float) -> Float {
    func window(_ x: Float, _ period: Float, _ width: Float) -> Float {
        let m = fmod(fmod(x, period) + period, period)
        return m < width ? sin(m / width * Float.pi) : 0.0
    }
    let closing = max(window(t, 3.7, 0.13), window(t + 1.3, 5.9, 0.13))
    return 1.0 - 0.9 * closing
}

public func eyeScale(state: CactusState, t: Float) -> EyeScale {
    switch state {
    case .idle, .speaking:
        return EyeScale(sx: 1.0, sy: blink(t))
    case .listening:
        return EyeScale(sx: 1.15, sy: 1.25)
    case .thinking:
        return EyeScale(sx: 1.0, sy: 1.0)
    case .working:
        return EyeScale(sx: 1.0, sy: 0.9 + 0.15 * sin(t * 6.0))
    case .error:
        return EyeScale(sx: 1.0, sy: 0.7)
    }
}

public func mouthLength(state: CactusState, t: Float, index: Int) -> Float {
    switch state {
    case .speaking:
        let freq: Float = 14.0 + Float(index) * 2.5
        let v = (sin(t * freq) + 1.0) * 0.5
        return 0.3 + 0.7 * v
    case .listening:
        return 0.25
    case .thinking:
        return 0.35
    case .working:
        return 0.5 + 0.4 * sin(t * 8.0 + Float(index))
    case .error:
        return 0.2
    case .idle:
        return 0.4
    }
}

public func effectivePose(state: CactusState, t: Float, animationsEnabled: Bool) -> EffectivePose {
    if !animationsEnabled {
        return EffectivePose(state: .idle, timeS: 0.0)
    }
    return EffectivePose(state: state, timeS: t)
}
