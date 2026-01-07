//
//  String+Normalizer.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation

extension String {
    /// Returns a normalized URL string.
    /// Adds https:// if missing.
    /// Leaves the string unchanged if it still cannot form a valid URL.
    var normalizedURLString: String {
        var text = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if user typed bare domain
        if !text.contains("://") {
            text = "https://" + text
        }
        
        // TODO: sus asf regex
        if text.matches(of: #/((http|https|file):\/\/)?([a-z0-9][a-z0-9\-_~\/:\?#\[\]@!$&'()\*+,;=]*)(\.[a-z0-9\-_~\/:\?#\[\]@!$&'()\*+,;=]+)+/#).isEmpty,
            let googleSearchURL = googleSearchURL(for: self) {
            return googleSearchURL
        }

        // If URL(string:) accepts it, return normalized version
        if let url = URL(string: text) {
            return url.absoluteString
        }
        
        // Otherwise return the original input (best-effort)
        return self
    }
    
    func googleSearchURL(for query: String) -> String? {
        guard let encoded = query
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        return "https://www.google.com/search?q=\(encoded)"
    }
}
