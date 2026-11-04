import SwiftUI

public struct ReducedMotionEnvironmentKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var animationsEnabled: Bool {
        get { !self.accessibilityReduceMotion }
        set { }
    }
}
