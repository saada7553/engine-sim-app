//
//  FilePersistance.swift
//  TileSurf
//
//  Created by Saad Ata on 11/27/25.
//

import Foundation

final class FilePersistence {
    private let baseFolder: URL
    
    init(directory: String) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        baseFolder = support
            .appendingPathComponent("TileSurf", isDirectory: true)
            .appendingPathComponent(directory, isDirectory: true)

        print(baseFolder.absoluteString)
        
        if !FileManager.default.fileExists(atPath: baseFolder.path) {
            try? FileManager.default.createDirectory(
                at: baseFolder,
                withIntermediateDirectories: true
            )
        }
    }
    
    func url(for file: String) -> URL {
        baseFolder.appendingPathComponent(file)
    }
    
    func save<T: Codable>(_ value: T, to file: String) {
        let url = url(for: file)
        
        let directory = url.deletingLastPathComponent()
        createDirectoryIfNeeded(at: directory)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ Failed to save \(file): \(error)")
        }
    }
    
    func load<T: Codable>(_ type: T.Type, from file: String) -> T? {
        let url = url(for: file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("❌ Failed to load \(file): \(error)")
            return nil
        }
    }
    
    /// Load a list of specified types from the instance's directory.
    func load<T: Codable>(_ type: T.Type) -> [T] {
        let fileList = listFiles()
        let items = fileList.compactMap { fileName in
            load(type, from: fileName)
        }
        return items
    }
    
    func delete(file: String) {
        let url = url(for: file)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("❌ Failed to delete \(file): \(error)")
        }
    }

    func listFiles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseFolder,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        
        return files.map { $0.lastPathComponent }
    }
    
    private func createDirectoryIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
    }
}
