//
//  BuiltInEngineSpecs.swift
//  engine-simulator
//
//  Built-in engines ship as authored .mr files without an EngineSpec attached.
//  The procedural 3D viewer needs geometry (bore, stroke, rod length, layout,
//  firing order) for every selectable engine, so we mirror the relevant values
//  from each built-in .mr here. Numbers below were read directly from the
//  corresponding file under assets/engines/atg-video-2/.
//

import Foundation

private let inchToMm: Double = 25.4

enum BuiltInEngineSpecs {
    /// Returns a fully-populated EngineSpec for the given built-in engine entry,
    /// or nil if the entry is not a known built-in.
    static func spec(for entry: EngineEntry) -> EngineSpec? {
        specsByStableId[entry.id]
    }

    private static let specsByStableId: [UUID: EngineSpec] = [
        toyota2jzId:    toyota2jz,
        gmLsV8Id:       gmLsV8,
        ferrariF136Id:  ferrariF136V8,
        lexusLFAId:     lexusLFAV10,
    ]

    // MARK: - Stable IDs (must match builtInCatalog in EngineLibrary.swift)

    private static let toyota2jzId   = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    private static let gmLsV8Id      = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
    private static let ferrariF136Id = UUID(uuidString: "11111111-0000-0000-0000-000000000003")!
    private static let lexusLFAId    = UUID(uuidString: "11111111-0000-0000-0000-000000000004")!

    // MARK: - Specs

    // Source: assets/engines/atg-video-2/03_2jz.mr
    private static let toyota2jz: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Toyota 2JZ", layout: .inline6)
        spec.id = toyota2jzId
        spec.boreMm = 86.0
        spec.strokeMm = 86.0
        spec.rodLengthMm = 142.0
        spec.compressionHeightMm = 32.8
        spec.redlineRpm = 6000
        spec.firingOrder = EngineLayout.inline6.firingOrder
        return spec
    }()

    // Source: assets/engines/atg-video-2/07_gm_ls.mr
    private static let gmLsV8: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "GM LS V8", layout: .v8_90)
        spec.id = gmLsV8Id
        spec.boreMm = 3.78 * inchToMm
        spec.strokeMm = 3.622 * inchToMm
        spec.rodLengthMm = 160.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 6500
        spec.firingOrder = EngineLayout.v8_90.firingOrder
        return spec
    }()

    // Source: assets/engines/atg-video-2/08_ferrari_f136_v8.mr
    private static let ferrariF136V8: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Ferrari F136 V8", layout: .v8_90)
        spec.id = ferrariF136Id
        spec.boreMm = 94.0
        spec.strokeMm = 81.0
        spec.rodLengthMm = 160.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 9000
        spec.firingOrder = EngineLayout.v8_90.firingOrder
        return spec
    }()

    // Source: assets/engines/atg-video-2/10_lfa_v10.mr
    private static let lexusLFAV10: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Lexus LFA V10", layout: .v10_72)
        spec.id = lexusLFAId
        spec.boreMm = 88.0
        spec.strokeMm = 79.0
        spec.rodLengthMm = 130.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 9000
        spec.firingOrder = EngineLayout.v10_72.firingOrder
        return spec
    }()
}

extension EngineEntry {
    /// Returns the editable user spec if present, otherwise the canned built-in spec.
    /// Used by views (e.g. procedural 3D) that need geometry for any selected engine.
    var effectiveSpec: EngineSpec? {
        spec ?? BuiltInEngineSpecs.spec(for: self)
    }
}
