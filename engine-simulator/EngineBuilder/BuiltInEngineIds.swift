//
//  BuiltInEngineIds.swift
//  engine-simulator
//
//  Stable UUIDs for every shipped built-in engine. One source of truth — all
//  other call sites (EngineLibrary catalog, BuiltInEngineSpecs, paywall
//  gate, anything that key-paths to a built-in) reference these constants
//  so we never re-type a UUID literal.
//

import Foundation

enum BuiltInEngineIds {
    static let geoMetroG10   = UUID(uuidString: "11111111-0000-0000-0000-000000000000")!
    static let toyota2jz     = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    static let gmLsV8        = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
    static let ferrariF136   = UUID(uuidString: "11111111-0000-0000-0000-000000000003")!
    static let lexusLFA      = UUID(uuidString: "11111111-0000-0000-0000-000000000004")!
    static let bmwM52B28     = UUID(uuidString: "11111111-0000-0000-0000-000000000005")!
    static let audiI5        = UUID(uuidString: "11111111-0000-0000-0000-000000000006")!
    static let hondaVtecF20C = UUID(uuidString: "11111111-0000-0000-0000-000000000007")!
    static let suzukiHayabusa = UUID(uuidString: "11111111-0000-0000-0000-000000000008")!
    static let subaruEJ25EH  = UUID(uuidString: "11111111-0000-0000-0000-000000000009")!
    static let subaruEJ25UH  = UUID(uuidString: "11111111-0000-0000-0000-00000000000a")!
    static let chevy454      = UUID(uuidString: "11111111-0000-0000-0000-00000000000d")!
    static let merlinV12     = UUID(uuidString: "11111111-0000-0000-0000-00000000000e")!
    static let ferrari412T2  = UUID(uuidString: "11111111-0000-0000-0000-00000000000f")!
}
