//
//  Environment.swift
//  LanguageFlow
//

import Foundation
import SwiftUI

#if DEBUG
struct DebugConfig {}

// MARK: - Environment
extension DebugConfig {
    private static let environmentStorageKey = "debug_config_environment"

    enum Environment: String, CaseIterable {
        case production
        case development

        var baseURL: String {
            switch self {
            case .production:
                return CommonConstants.baseURL
            case .development:
                return "http://192.168.0.244:8001/podcast"
            }
        }

        var displayName: String {
            switch self {
            case .production:
                return "线上"
            case .development:
                return "本地"
            }
        }
    }

    static var environment: Environment {
        guard
            let raw = UserDefaults.standard.string(forKey: environmentStorageKey),
            let env = Environment(rawValue: raw)
        else {
            return .production
        }
        return env
    }

    static var baseURL: String {
        environment.baseURL
    }

    static func setEnvironment(_ environment: Environment?) {
        if let environment {
            UserDefaults.standard.set(environment.rawValue, forKey: environmentStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: environmentStorageKey)
        }
    }
}

// MARK: - Reciting
nonisolated
extension DebugConfig {
    static let recitingDebugEnabledKey = "debug_config_reciting_debug_enabled"

    static var recitingDebugEnabled: Bool {
        if UserDefaults.standard.object(forKey: recitingDebugEnabledKey) != nil {
            return UserDefaults.standard.bool(forKey: recitingDebugEnabledKey)
        }
        return true
    }

    static func setRecitingDebugEnabled(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: recitingDebugEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recitingDebugEnabledKey)
        }
    }
}
#endif
