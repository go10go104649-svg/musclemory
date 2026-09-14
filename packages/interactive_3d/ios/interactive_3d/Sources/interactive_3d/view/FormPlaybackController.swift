import SceneKit
import UIKit

/// Opt-in playback for the single bench-press prototype. The GLB contains the
/// rig, equipment and baked animation; this class only controls its clock.
final class FormPlaybackController: NSObject {
    private weak var view: SCNView?
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var playhead: CFTimeInterval = 0
    private var duration: CFTimeInterval = 4
    private var speed = 1.0

    init(view: SCNView) {
        self.view = view
        super.init()
        guard let scene = view.scene else { return }
        view.allowsCameraControl = false
        view.gestureRecognizers?.forEach { $0.isEnabled = false }
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = false
        scene.rootNode.enumerateChildNodes { node, _ in
            for key in node.animationKeys {
                guard let original = node.animationPlayer(forKey: key)?.animation,
                      let animation = original.copy() as? SCNAnimation else { continue }
                self.duration = max(self.duration, animation.duration)
                animation.usesSceneTimeBase = true
                animation.startDelay = 0
                animation.timeOffset = 0
                animation.repeatCount = .greatestFiniteMagnitude
                animation.isRemovedOnCompletion = false
                node.removeAnimation(forKey: key, blendOutDuration: 0)
                node.addAnimation(animation, forKey: key)
            }
            if node.light != nil { node.removeFromParentNode() }
        }
        let camera = SCNNode()
        camera.name = "MUSCLEMORY fixed form camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.225
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 20
        camera.position = SCNVector3(2.8, 2.5, 3.4)
        camera.look(at: SCNVector3(0, 0.58, 0.13))
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 280
        scene.rootNode.addChildNode(ambient)
        for (index, position, intensity) in [
            (0, SCNVector3(-2, 4, 3), CGFloat(850)),
            (1, SCNVector3(3, 3, 1), CGFloat(350)),
            (2, SCNVector3(0, 3, -3), CGFloat(650))
        ] {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .directional
            node.light?.intensity = intensity
            node.position = position
            node.look(at: SCNVector3(0, 0.5, 0))
            if index == 0 {
                node.light?.castsShadow = true
                node.light?.shadowColor = UIColor.black.withAlphaComponent(0.3)
                node.light?.shadowRadius = 4
                node.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
                node.light?.orthographicScale = 3
            }
            scene.rootNode.addChildNode(node)
        }
        view.sceneTime = 0
    }

    func configure(playing: Bool, speed: Double, bodyViewAngle: Int? = nil) {
        if let angle = bodyViewAngle, let camera = view?.pointOfView {
            // glTF converts production Z-up to Y-up; front faces positive Z.
            let positions = [SCNVector3(0, 0.85, 4), SCNVector3(4, 0.85, 0), SCNVector3(0, 0.85, -4)]
            camera.position = positions[min(2, max(0, angle))]
            camera.eulerAngles = SCNVector3(0, Float(angle == 1 ? Double.pi / 2 : angle == 2 ? Double.pi : 0), 0)
            camera.camera?.orthographicScale = 1.0
            // Camera-relative studio lighting preserves readable grey and red
            // surfaces on all three sides of the same athlete.
            let yaw = Float(angle == 1 ? Double.pi / 2 : angle == 2 ? Double.pi : 0)
            var lightIndex = 0
            view?.scene?.rootNode.enumerateChildNodes { node, _ in
                if node.light?.type == .ambient { node.light?.intensity = 600 }
                if node.light?.type == .directional {
                    let positions = [SCNVector3(-2, 3, 4), SCNVector3(3, 2, 2), SCNVector3(0, 3, -3)]
                    let p = positions[min(lightIndex, 2)]
                    node.position = SCNVector3(p.x * cos(yaw) + p.z * sin(yaw), p.y,
                                              -p.x * sin(yaw) + p.z * cos(yaw))
                    node.look(at: SCNVector3(0, 0.85, 0))
                    node.light?.intensity = CGFloat([1100, 600, 650][min(lightIndex, 2)])
                    node.light?.castsShadow = false
                    lightIndex += 1
                }
            }
        }
        // Account for the old rate before applying a new one. Pausing does not
        // change the current pose, and speed changes do not reset the cycle.
        advance(to: CACurrentMediaTime())
        self.speed = speed.isFinite ? min(2, max(0.25, speed)) : 1
        displayLink?.invalidate()
        displayLink = nil
        lastTime = nil
        view?.rendersContinuously = playing
        if playing {
            lastTime = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            } else {
                link.preferredFramesPerSecond = 60
            }
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        view?.setNeedsDisplay()
    }

    private func advance(to time: CFTimeInterval) {
        guard let last = lastTime else { return }
        playhead = (playhead + max(0, time - last) * speed).truncatingRemainder(dividingBy: duration)
        lastTime = time
        view?.sceneTime = playhead
    }

    @objc private func tick(_ link: CADisplayLink) {
        advance(to: link.timestamp)
    }

    func dispose() {
        displayLink?.invalidate()
        displayLink = nil
        lastTime = nil
        view?.rendersContinuously = false
        view?.isPlaying = false
    }
}
