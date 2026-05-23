//
//  EnginePreviewRenderer.swift
//  engine-simulator
//
//  Renders an engine to a still image, once, and caches it (in memory and on
//  disk). The community browser shows these cached images in its list instead
//  of spinning up a live SceneKit view per row — dozens of live 3D views, even
//  static ones, would be far too expensive. Tapping a card opens a single live
//  rotating view (EnginePreview3DView); everywhere else it's just a bitmap.
//
//  Rendering is serialized through an actor so a screen full of cards can't
//  fire dozens of GPU snapshots at once, and every failure path returns nil
//  rather than throwing so a bad spec just shows a placeholder.
//

import SceneKit
import CryptoKit
#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

actor EnginePreviewRenderer {
    static let shared = EnginePreviewRenderer()

    /// Square render size. Cards display smaller; the extra resolution keeps the
    /// thumbnail crisp on Retina without re-rendering per display size.
    private static let renderSide: CGFloat = 320

    private let memoryCache = NSCache<NSString, PlatformImage>()
    /// Coalesces concurrent requests for the same engine into one render.
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    private let device = MTLCreateSystemDefaultDevice()

    /// A cached or freshly-rendered thumbnail for `spec`, or nil if rendering
    /// isn't possible (no Metal device, bad geometry). Identical engines share
    /// a cache entry, so re-listing the same engine never re-renders.
    func image(for spec: EngineSpec) async -> PlatformImage? {
        let key = Self.cacheKey(for: spec)

        if let cached = memoryCache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<PlatformImage?, Never> { [spec] in
            if let disk = Self.loadFromDisk(key: key) { return disk }
            guard let rendered = self.render(spec: spec) else { return nil }
            Self.saveToDisk(rendered, key: key)
            return rendered
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memoryCache.setObject(result, forKey: key as NSString) }
        return result
    }

    // MARK: - Rendering

    private func render(spec: EngineSpec) -> PlatformImage? {
        guard let device = device else {
            print("EnginePreviewRenderer: no Metal device; skipping thumbnail.")
            return nil
        }
        let scene = EnginePreviewScene.make(spec: spec, background: .clear)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        let side = Self.renderSide
        let image = renderer.snapshot(atTime: 0,
                                      with: CGSize(width: side, height: side),
                                      antialiasingMode: .multisampling4X)
        // A 1×1 (or empty) image means the snapshot failed; treat as no image.
        guard image.size.width > 1 else { return nil }
        return image
    }

    // MARK: - Cache key

    /// Deterministic across launches (unlike `Hasher`, which is seeded per
    /// process) so the on-disk cache survives relaunches. Keyed on the fields
    /// that actually change the rendered geometry.
    private static func cacheKey(for spec: EngineSpec) -> String {
        let raw = [
            spec.layout.rawValue,
            fmt(spec.boreMm), fmt(spec.strokeMm), fmt(spec.rodLengthMm),
            fmt(spec.compressionHeightMm), fmt(spec.camDurationDeg), fmt(spec.camLiftMm),
            fmt(spec.camLobeSeparationDeg), fmt(spec.camAdvanceDeg), fmt(spec.camBaseRadiusIn),
            spec.firingOrder.map(String.init).joined(separator: "-")
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

    // MARK: - Disk cache

    private static var cacheDirectory: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("EnginePreviews", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            catch { print("EnginePreviewRenderer: cache dir create failed: \(error)"); return nil }
        }
        return dir
    }

    private static func diskURL(key: String) -> URL? {
        cacheDirectory?.appendingPathComponent("\(key).png")
    }

    private static func loadFromDisk(key: String) -> PlatformImage? {
        guard let url = diskURL(key: key),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return PlatformImage(data: data)
    }

    private static func saveToDisk(_ image: PlatformImage, key: String) {
        guard let url = diskURL(key: key), let data = pngData(image) else { return }
        do { try data.write(to: url) }
        catch { print("EnginePreviewRenderer: cache write failed: \(error)") }
    }

    private static func pngData(_ image: PlatformImage) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }
}
