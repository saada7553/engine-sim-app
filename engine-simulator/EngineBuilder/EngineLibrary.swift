//
//  EngineLibrary.swift
//  engine-simulator
//
//  Single source of truth for the engines shown in the sidebar.
//  Combines built-in (bundle) engines with user-built engines that live
//  in Application Support and are described by EngineSpec JSON files.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Public model

/// A library entry as the sidebar / view-model see it. Built-in engines have
/// no spec (they ship as authored .mr files); user-built engines do.
struct EngineEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var displacementLabel: String
    var cylinderCount: Int
    var mrPath: String          // absolute path to .mr file the C++ compiler will load
    var spec: EngineSpec?       // nil for built-in entries
    var isUserBuilt: Bool { spec != nil }

    static func == (lhs: EngineEntry, rhs: EngineEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Built-in catalog

/// Hardcoded list of bundle engines we expose. Each one points at a real .mr file
/// shipped under Resources/assets/engines/...
private struct BuiltInEntry {
    let name: String
    let displacement: String
    let cylinders: Int
    let relativePath: String   // path inside assets/, e.g. "engines/atg-video-2/03_2jz.mr"
    let stableUUID: UUID
}

private let builtInCatalog: [BuiltInEntry] = [
    // Metro lives at index 0 so it shows up first in the sidebar and acts
    // as the free / default selection. The other engines below are
    // Pro-gated; selecting any of them runs through the paywall.
    BuiltInEntry(name: "Geo Metro G10", displacement: "1.0L", cylinders: 3,
                 relativePath: "engines/atg-video-2/00_geo_metro_g10.mr",
                 stableUUID: BuiltInEngineIds.geoMetroG10),
    BuiltInEntry(name: "Suzuki Hayabusa (Bike)", displacement: "1.3L", cylinders: 4,
                 relativePath: "engines/atg-video-1/04_hayabusa.mr",
                 stableUUID: BuiltInEngineIds.suzukiHayabusa),
    BuiltInEntry(name: "Honda F20C (VTEC)", displacement: "2.0L", cylinders: 4,
                 relativePath: "engines/atg-video-1/05_honda_vtec.mr",
                 stableUUID: BuiltInEngineIds.hondaVtecF20C),
    BuiltInEntry(name: "Audi 2.2 I5", displacement: "2.2L", cylinders: 5,
                 relativePath: "engines/audi/i5.mr",
                 stableUUID: BuiltInEngineIds.audiI5),
    BuiltInEntry(name: "Subaru EJ25 (Equal-Length Headers)", displacement: "2.5L", cylinders: 4,
                 relativePath: "engines/atg-video-2/01_subaru_ej25_eh.mr",
                 stableUUID: BuiltInEngineIds.subaruEJ25EH),
    BuiltInEntry(name: "Subaru EJ25 (Boxer Rumble)", displacement: "2.5L", cylinders: 4,
                 relativePath: "engines/atg-video-2/02_subaru_ej25_uh.mr",
                 stableUUID: BuiltInEngineIds.subaruEJ25UH),
    BuiltInEntry(name: "BMW M52B28", displacement: "2.8L", cylinders: 6,
                 relativePath: "engines/bmw/M52B28.mr",
                 stableUUID: BuiltInEngineIds.bmwM52B28),
    BuiltInEntry(name: "Toyota 2JZ", displacement: "3.0L", cylinders: 6,
                 relativePath: "engines/atg-video-2/03_2jz.mr",
                 stableUUID: BuiltInEngineIds.toyota2jz),
    BuiltInEntry(name: "Ferrari 412 T2 (F1)", displacement: "3.0L", cylinders: 12,
                 relativePath: "engines/atg-video-2/12_ferrari_412_t2.mr",
                 stableUUID: BuiltInEngineIds.ferrari412T2),
    BuiltInEntry(name: "Ferrari F136 V8", displacement: "4.5L", cylinders: 8,
                 relativePath: "engines/atg-video-2/08_ferrari_f136_v8.mr",
                 stableUUID: BuiltInEngineIds.ferrariF136),
    BuiltInEntry(name: "Lexus LFA V10", displacement: "4.8L", cylinders: 10,
                 relativePath: "engines/atg-video-2/10_lfa_v10.mr",
                 stableUUID: BuiltInEngineIds.lexusLFA),
    BuiltInEntry(name: "GM LS V8", displacement: "5.7L", cylinders: 8,
                 relativePath: "engines/atg-video-2/07_gm_ls.mr",
                 stableUUID: BuiltInEngineIds.gmLsV8),
    BuiltInEntry(name: "Chevy 454 Big Block", displacement: "7.4L", cylinders: 8,
                 relativePath: "engines/chevrolet/chev_truck_454.mr",
                 stableUUID: BuiltInEngineIds.chevy454),
    BuiltInEntry(name: "Rolls-Royce Merlin V12", displacement: "27.0L", cylinders: 12,
                 relativePath: "engines/atg-video-2/11_merlin_v12.mr",
                 stableUUID: BuiltInEngineIds.merlinV12),
]

// MARK: - Persistence layout

private let userEnginesFolderName = "UserEngines"
private let specExtension = "json"
private let mrExtension = "mr"

private enum LibraryPaths {
    static var supportDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls.first ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "engine-simulator"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    static var userEnginesDirectory: URL {
        supportDirectory.appendingPathComponent(userEnginesFolderName, isDirectory: true)
    }

    static func mrFileURL(for spec: EngineSpec) -> URL {
        userEnginesDirectory.appendingPathComponent("\(spec.id.uuidString).\(mrExtension)")
    }

    static func specFileURL(for spec: EngineSpec) -> URL {
        userEnginesDirectory.appendingPathComponent("\(spec.id.uuidString).\(specExtension)")
    }
}

// MARK: - EngineLibrary

final class EngineLibrary: ObservableObject {
    static let shared = EngineLibrary()

    @Published private(set) var entries: [EngineEntry] = []
    @Published var selectedEngineId: UUID?

    /// IDs that don't require a Pro entitlement to load. Anything not in
    /// this set runs through the paywall on selection.
    static let freeEngineIds: Set<UUID> = [
        BuiltInEngineIds.geoMetroG10
    ]

    private init() {
        ensureUserEnginesDirectory()
        reloadEntries()
        selectedEngineId = entries.first?.id   // default selection = first built-in
    }

    /// Whether selecting `entryId` should require a Pro entitlement. Free
    /// engines and the engine that's already selected pass through; every
    /// other engine (built-in or user-saved) is gated.
    func isPaywalled(_ entryId: UUID) -> Bool {
        if Self.freeEngineIds.contains(entryId) { return false }
        if selectedEngineId == entryId { return false }
        return true
    }

    // MARK: Public API

    func saveUserEngine(_ spec: EngineSpec) {
        let mrText = MRWriter.script(for: spec)
        let mrURL = LibraryPaths.mrFileURL(for: spec)
        let specURL = LibraryPaths.specFileURL(for: spec)

        do {
            try mrText.data(using: .utf8)?.write(to: mrURL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(spec).write(to: specURL)
        } catch {
            print("EngineLibrary: failed to write user engine \(spec.name): \(error)")
            return
        }

        reloadEntries()
        selectedEngineId = spec.id
    }

    func deleteUserEngine(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.isUserBuilt,
              let spec = entry.spec else { return }
        let mrURL = LibraryPaths.mrFileURL(for: spec)
        let specURL = LibraryPaths.specFileURL(for: spec)
        try? FileManager.default.removeItem(at: mrURL)
        try? FileManager.default.removeItem(at: specURL)

        let wasSelected = selectedEngineId == id
        reloadEntries()
        if wasSelected { selectedEngineId = entries.first?.id }
    }

    func entry(for id: UUID) -> EngineEntry? {
        entries.first(where: { $0.id == id })
    }

    var selectedEntry: EngineEntry? {
        guard let id = selectedEngineId else { return nil }
        return entry(for: id)
    }

    // MARK: Loading

    private func reloadEntries() {
        var combined: [EngineEntry] = builtInEntries()
        combined.append(contentsOf: loadUserEntries())
        entries = combined
    }

    private func builtInEntries() -> [EngineEntry] {
        guard let resourcePath = Bundle.main.resourcePath else { return [] }
        let assetsPath = (resourcePath as NSString).appendingPathComponent("assets")

        return builtInCatalog.compactMap { item in
            let mrPath = (assetsPath as NSString).appendingPathComponent(item.relativePath)
            guard FileManager.default.fileExists(atPath: mrPath) else { return nil }
            return EngineEntry(
                id: item.stableUUID,
                name: item.name,
                displacementLabel: item.displacement,
                cylinderCount: item.cylinders,
                mrPath: mrPath,
                spec: nil
            )
        }
    }

    private func loadUserEntries() -> [EngineEntry] {
        let dir = LibraryPaths.userEnginesDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        var out: [EngineEntry] = []
        for url in contents where url.pathExtension == specExtension {
            guard let data = try? Data(contentsOf: url),
                  let spec = try? decoder.decode(EngineSpec.self, from: data) else { continue }
            let mrURL = LibraryPaths.mrFileURL(for: spec)
            guard FileManager.default.fileExists(atPath: mrURL.path) else { continue }

            let displacement = String(format: "%.1fL", spec.displacementLitres)
            out.append(EngineEntry(
                id: spec.id,
                name: spec.name,
                displacementLabel: displacement,
                cylinderCount: spec.layout.cylinderCount,
                mrPath: mrURL.path,
                spec: spec
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    private func ensureUserEnginesDirectory() {
        let dir = LibraryPaths.userEnginesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
