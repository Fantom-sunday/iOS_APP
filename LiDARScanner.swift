import ARKit
import RealityKit
import SwiftUI
import Observation
import simd


struct SurfaceAreas: Sendable {
    var wall: Float = 0
    var floor: Float = 0
    var ceiling: Float = 0
    var table: Float = 0
    var seat: Float = 0
    var window: Float = 0
    var door: Float = 0
    var other: Float = 0
    var total: Float { wall + floor + ceiling + table + seat + window + door + other }
}

struct MeshStats: Sendable {
    var areas = SurfaceAreas()
    var footprintArea: Float = 0
    var ceilingHeight: Float?
    var boundingHeight: Float = 0
}

private struct AnchorBox: @unchecked Sendable {
    let anchors: [ARMeshAnchor]
}


enum MeshAnalyzer {
    static func analyze(_ anchors: [ARMeshAnchor]) -> MeshStats {
        var areas = SurfaceAreas()
        var cells = Set<SIMD2<Int32>>()
        var floorY: Float = 0, floorWeight: Float = 0
        var ceilingY: Float = 0, ceilingWeight: Float = 0
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        let cellSize: Float = 0.3

        for anchor in anchors {
            let geometry = anchor.geometry
            let vertexSource = geometry.vertices
            let faces = geometry.faces
            guard vertexSource.count > 0, faces.count > 0 else { continue }

            let transform = anchor.transform
            let vertexBase = vertexSource.buffer.contents()
            var world = [SIMD3<Float>]()
            world.reserveCapacity(vertexSource.count)
            for i in 0..<vertexSource.count {
                let offset = vertexSource.offset + vertexSource.stride * i
                let x = vertexBase.load(fromByteOffset: offset, as: Float.self)
                let y = vertexBase.load(fromByteOffset: offset + 4, as: Float.self)
                let z = vertexBase.load(fromByteOffset: offset + 8, as: Float.self)
                let p = transform * SIMD4<Float>(x, y, z, 1)
                world.append(SIMD3<Float>(p.x, p.y, p.z))
                if p.y.isFinite { minY = min(minY, p.y); maxY = max(maxY, p.y) }
            }

            let faceBase = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex
            let perFace = faces.indexCountPerPrimitive
            let classification = geometry.classification
            let classBase = classification?.buffer.contents()

            for f in 0..<faces.count {
                let o = f * perFace * bytesPerIndex
                let i0 = Int(faceBase.load(fromByteOffset: o, as: UInt32.self))
                let i1 = Int(faceBase.load(fromByteOffset: o + bytesPerIndex, as: UInt32.self))
                let i2 = Int(faceBase.load(fromByteOffset: o + 2 * bytesPerIndex, as: UInt32.self))
                guard i0 < world.count, i1 < world.count, i2 < world.count else { continue }

                let a = world[i0], b = world[i1], c = world[i2]
                let area = 0.5 * simd_length(simd_cross(b - a, c - a))
                guard area.isFinite, area > 0 else { continue }

                let centroid = (a + b + c) / 3
                if abs(centroid.x) < 1e5, abs(centroid.z) < 1e5, centroid.x.isFinite, centroid.z.isFinite {
                    cells.insert(SIMD2<Int32>(
                        Int32((centroid.x / cellSize).rounded(.down)),
                        Int32((centroid.z / cellSize).rounded(.down))
                    ))
                }

                var kind = ARMeshClassification.none
                if let classification, let classBase {
                    let raw = classBase.load(
                        fromByteOffset: classification.offset + classification.stride * f,
                        as: UInt8.self
                    )
                    kind = ARMeshClassification(rawValue: Int(raw)) ?? .none
                }

                switch kind {
                case .wall:    areas.wall    += area
                case .floor:
                    areas.floor += area
                    floorY      += centroid.y * area
                    floorWeight += area
                case .ceiling:
                    areas.ceiling  += area
                    ceilingY       += centroid.y * area
                    ceilingWeight  += area
                case .table:   areas.table  += area
                case .seat:    areas.seat   += area
                case .window:  areas.window += area
                case .door:    areas.door   += area
                case .none:    areas.other  += area
                @unknown default: areas.other += area
                }
            }
        }

        var ceilingHeight: Float?
        if floorWeight > 1, ceilingWeight > 1 {
            let h = ceilingY / ceilingWeight - floorY / floorWeight
            if (1.8...8).contains(h) { ceilingHeight = h }
        }

        return MeshStats(
            areas: areas,
            footprintArea: Float(cells.count) * cellSize * cellSize,
            ceilingHeight: ceilingHeight,
            boundingHeight: maxY > minY ? maxY - minY : 0
        )
    }
}


@Observable
@MainActor
final class LiDARScanner {
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    private(set) var stats = MeshStats()
    private(set) var isRunning = false
    private(set) var ambientIntensity: Double = 1000
    private(set) var colorTemperature: Double = 6500
    private(set) var trackingHint: String?
    var showMesh = true

    @ObservationIgnored private var _arView: ARView?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isAnalyzing = false
    @ObservationIgnored private var hasLightSample = false

    var arView: ARView {
        if let existing = _arView { return existing }
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        _arView = view
        applyDebugOptions()
        return view
    }

    var coverage: Double { min(1, Double(stats.areas.total) / 40) }
    var isReady: Bool { stats.areas.total >= 14 && stats.areas.floor >= 1.5 }

    var hint: String? {
        if let trackingHint { return trackingHint }
        if isRunning, stats.areas.total < 1 { return "Медленно води телефоном по комнате" }
        if stats.areas.floor > 3, stats.areas.ceiling < 1 { return "Наведи камеру на потолок, так точнее" }
        return nil
    }

    func makeProfile() -> EnvironmentProfile {
        EnvironmentProfile(
            areas: stats.areas,
            footprintArea: stats.footprintArea,
            ceilingHeight: stats.ceilingHeight,
            boundingHeight: stats.boundingHeight,
            ambientIntensity: ambientIntensity,
            colorTemperature: colorTemperature
        )
    }

    func start() {
        guard Self.isSupported else { return }
        arView.session.run(makeConfiguration())
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        _arView?.session.pause()
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reset() {
        guard Self.isSupported else { return }
        stats = MeshStats()
        hasLightSample = false
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        if pollTask == nil { startPolling() }
        isRunning = true
    }

    func toggleMesh() {
        showMesh.toggle()
        applyDebugOptions()
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.isLightEstimationEnabled = true
        return config
    }

    private func applyDebugOptions() {
        _arView?.debugOptions = showMesh ? [.showSceneUnderstanding] : []
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        guard let session = _arView?.session, let frame = session.currentFrame else { return }
        updateTracking(frame.camera.trackingState)

        if let estimate = frame.lightEstimate {
            let intensity = Double(estimate.ambientIntensity)
            let temperature = Double(estimate.ambientColorTemperature)
            if hasLightSample {
                let k = 0.15
                ambientIntensity  += (intensity    - ambientIntensity)  * k
                colorTemperature  += (temperature  - colorTemperature)  * k
            } else {
                ambientIntensity = intensity
                colorTemperature = temperature
                hasLightSample = true
            }
        }

        guard !isAnalyzing else { return }
        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !anchors.isEmpty else { return }

        isAnalyzing = true
        let box = AnchorBox(anchors: anchors)
        let result = await Task.detached(priority: .utility) {
            MeshAnalyzer.analyze(box.anchors)
        }.value
        stats = result
        isAnalyzing = false
    }

    private func updateTracking(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal: trackingHint = nil
        case .notAvailable: trackingHint = "Трекинг недоступен"
        case .limited(let reason):
            switch reason {
            case .initializing:        trackingHint = "Запускаем трекинг…"
            case .excessiveMotion:     trackingHint = "Двигайся медленнее"
            case .insufficientFeatures: trackingHint = "Мало деталей: добавь света или подойди ближе"
            case .relocalizing:        trackingHint = "Восстанавливаем положение…"
            @unknown default:          trackingHint = nil
            }
        @unknown default: trackingHint = nil
        }
    }
}


struct LiDARCameraView: UIViewRepresentable {
    let scanner: LiDARScanner
    func makeUIView(context: Context) -> ARView { scanner.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
