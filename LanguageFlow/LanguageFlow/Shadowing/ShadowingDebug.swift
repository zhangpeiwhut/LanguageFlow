//
//  ShadowingDebug.swift
//  LanguageFlow
//

import Foundation

nonisolated
enum ShadowingDebug {
    static var enabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "ShadowingDebug") != nil {
            return UserDefaults.standard.bool(forKey: "ShadowingDebug")
        }
        return true
        #else
        return false
        #endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[Shadowing] \(message())")
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = ["\(nsError.domain)(\(nsError.code))"]

        let message = nsError.localizedDescription
        if !message.isEmpty {
            parts.append(message)
        }
        if let reason = nsError.localizedFailureReason, !reason.isEmpty, reason != message {
            parts.append(reason)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)(\(underlying.code)) \(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }

    static func fileSummary(url: URL) -> String {
        let name = url.lastPathComponent
        let ext = url.pathExtension.isEmpty ? "-" : url.pathExtension
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            return "\(name) (\(ext)) missing"
        }
        let size: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        } catch {
            size = -1
        }
        return "\(name) (\(ext)) size=\(size)"
    }
}
