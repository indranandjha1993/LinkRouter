//
//  URLExtensions.swift
//  LinkRouter
//
//  Created by Claude Code on 05.01.2026.
//

import Foundation

extension Bundle {
    /// Human-readable app name that never crashes: not every app declares
    /// CFBundleName (some only set CFBundleDisplayName, or neither).
    var appDisplayName: String {
        (infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }
}

extension URL {
    func matchesHost(_ configuredHost: String) -> Bool {
        if configuredHost.isEmpty {
            return true
        }

        guard let urlHost = self.host()?.lowercased() else { return false }
        let appHost = configuredHost.lowercased()
        return urlHost == appHost || urlHost.hasSuffix("." + appHost)
    }
}
