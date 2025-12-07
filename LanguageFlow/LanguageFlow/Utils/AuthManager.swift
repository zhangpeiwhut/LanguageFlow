//
//  AuthManager.swift
//  LanguageFlow
//

import Foundation
import Observation
import UIKit
import Alamofire

@Observable
final class AuthManager {
    static let shared = AuthManager()

    private let baseURL = "https://elegantfish.online/podcast"
    private let cacheInterval: TimeInterval = 60 * 60

    private var deviceUUID: String
    private var accessToken: String?
    var isVIP: Bool = false
    var vipExpireTime: Date?
    var deviceStatus: DeviceStatus = .active

    private var lastRefreshTime: Date?
    private var isRefreshing: Bool = false

    private init() {
        deviceUUID = KeychainManager.getOrCreateDeviceUUID()
        accessToken = KeychainManager.getToken()
    }

    func syncUserStatus(force: Bool = false) async throws {
        guard !isRefreshing else {
            print("[Info] User status sync already in progress, skipping...")
            return
        }

        if !force, let lastRefresh = lastRefreshTime {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < cacheInterval {
                print("[Info] User status cached (refreshed \(Int(timeSinceLastRefresh))s ago), skipping...")
                return
            }
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let parameters: [String: Any] = [
            "device_uuid": deviceUUID,
            "device_name": UIDevice.current.name,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]

        let response = try await AF.request(
            "\(baseURL)/auth/register",
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default
        )
        .validate()
        .serializingDecodable(AuthResponse.self, decoder: Self.millisecondsDecoder)
        .value

        self.accessToken = response.data.accessToken
        KeychainManager.saveToken(response.data.accessToken)

        self.isVIP = response.data.isVIP
        self.vipExpireTime = response.data.vipExpireTime
        self.deviceStatus = response.data.deviceStatus
        self.lastRefreshTime = Date()

        print("[Info] User status synced: isVIP=\(self.isVIP), status=\(self.deviceStatus)")

        if self.deviceStatus == .kicked {
            self.showKickedAlert()
        }
    }

    func getDeviceUUID() -> String {
        return deviceUUID
    }

    func getAuthHeaders() -> HTTPHeaders {
        guard let token = accessToken ?? KeychainManager.getToken() else {
            print("[Warning] No access token available")
            return [:]
        }
        return ["Authorization": "Bearer \(token)"]
    }

    private func showKickedAlert() {
        // TODO: zhangpei
        print("[Info] Device kicked: 您的会员已在其他设备激活")
    }

    private static var millisecondsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
