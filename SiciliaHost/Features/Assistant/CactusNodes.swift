import Foundation

public enum CactusNodes {
    public static let root = "SiciliaHost_Assistant_Root"
    public static let rig = "Character_Animated_Rig"
    public static let group = "FicoDIndia_Group"
    public static let palaCenter = "Pala_Centrale_Verde"
    public static let palaLeft = "Pala_Sinistra_Gialla"
    public static let palaRight = "Pala_Destra_VerdeChiaro"

    public static let fruits = ["Frutto_Rosso_1", "Frutto_Rosso_2", "Frutto_Rosso_3"]
    public static let detailsSuffix = "_Details"
    public static let faceRoot = "Assistant_Face_Root"
}

public struct FaceChild: Equatable, Sendable {
    public let childCount: Int
    public let x: Float

    public init(childCount: Int, x: Float) {
        self.childCount = childCount
        self.x = x
    }
}

public struct FaceLayout: Equatable, Sendable {
    public let visor: Int
    public let leftEye: Int
    public let rightEye: Int
    public let mouth: Int

    public init(visor: Int, leftEye: Int, rightEye: Int, mouth: Int) {
        self.visor = visor
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.mouth = mouth
    }
}

public func classifyFace(children: [FaceChild]) -> FaceLayout? {
    guard children.count == 4 else { return nil }
    guard let mouth = children.indices.filter({ children[$0].childCount == 5 }).first,
          children.indices.filter({ children[$0].childCount == 5 }).count == 1 else { return nil }
    guard let visor = children.indices.filter({ children[$0].childCount == 2 }).first,
          children.indices.filter({ children[$0].childCount == 2 }).count == 1 else { return nil }

    let eyes = children.indices.filter { $0 != mouth && $0 != visor }
    guard eyes.count == 2 else { return nil }

    let (a, b) = (eyes[0], eyes[1])
    if children[a].x == children[b].x { return nil }
    let left = children[a].x < children[b].x ? a : b
    let right = left == a ? b : a
    if children[left].x >= 0 || children[right].x <= 0 { return nil }

    return FaceLayout(visor: visor, leftEye: left, rightEye: right, mouth: mouth)
}

public func orderByX(_ xs: [Float]) -> [Int] {
    return xs.indices.sorted { xs[$0] < xs[$1] }
}

public func fruitGlowNodes<N>(
    fruit: N,
    nameOf: (N) -> String?,
    childrenOf: (N) -> [N]
) -> [N] {
    var out: [N] = []
    var stack = [fruit]
    while !stack.isEmpty {
        let n = stack.removeLast()
        if let name = nameOf(n), name.hasSuffix(CactusNodes.detailsSuffix) {
            continue
        }
        out.append(n)
        stack.append(contentsOf: childrenOf(n))
    }
    return out
}
