import Foundation
import SceneKit
import SwiftUI

/// Motore 3D per l'avatar Cactus su iOS via SceneKit nativo Apple (equivalente a Filament su Android).
public final class CactusAvatarEngine: @unchecked Sendable {
    public let scene: SCNScene
    public let cameraNode: SCNNode
    private var fruitNodes: [SCNNode] = []
    private var leftEyeNode: SCNNode?
    private var rightEyeNode: SCNNode?
    private var mouthNodes: [SCNNode] = []

    public init() {
        self.scene = SCNScene()

        // Configurazione camera (30° FOV come su Android)
        let cam = SCNCamera()
        cam.fieldOfView = 30.0
        let cNode = SCNNode()
        cNode.camera = cam
        cNode.position = SCNVector3(x: 0, y: 0.4, z: 6.2)
        self.cameraNode = cNode
        scene.rootNode.addChildNode(cNode)

        // Luci (bianca e ciano di controluce)
        let mainLight = SCNLight()
        mainLight.type = .directional
        mainLight.color = UIColor.white
        let lightNode = SCNNode()
        lightNode.light = mainLight
        lightNode.position = SCNVector3(x: 2, y: 4, z: 5)
        scene.rootNode.addChildNode(lightNode)

        let backLight = SCNLight()
        backLight.type = .directional
        backLight.color = UIColor(red: 0.0, green: 0.87, blue: 1.0, alpha: 1.0)
        let backNode = SCNNode()
        backNode.light = backLight
        backNode.position = SCNVector3(x: -2, y: -2, z: -3)
        scene.rootNode.addChildNode(backNode)
    }

    /// Applica la posa procedurale calcolata da `CactusPose` a ciascun nodo 3D.
    public func applyPose(state: CactusState, timeS: Float) {
        // Applica rimbalzo dei tre frutti
        for idx in 0..<fruitNodes.count {
            let p = fruitPose(state: state, t: timeS, index: idx)
            fruitNodes[idx].position.y = p.dy
            fruitNodes[idx].scale = SCNVector3(x: p.sx, y: p.sy, z: 1.0)
        }

        // Applica battito/scala degli occhi
        let eye = eyeScale(state: state, t: timeS)
        leftEyeNode?.scale = SCNVector3(x: eye.sx, y: eye.sy, z: 1.0)
        rightEyeNode?.scale = SCNVector3(x: eye.sx, y: eye.sy, z: 1.0)

        // Applica barrette della bocca
        for idx in 0..<mouthNodes.count {
            let h = mouthLength(state: state, t: timeS, index: idx)
            mouthNodes[idx].scale.y = h
        }
    }
}
