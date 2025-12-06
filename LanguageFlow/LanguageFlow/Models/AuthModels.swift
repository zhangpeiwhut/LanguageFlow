//
//  AuthModels.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/6/25.
//

import Foundation

nonisolated
struct AuthResponse: Codable {
    let code: Int
    let message: String
    let data: UserData
}

nonisolated
struct UserData: Codable {
    let isVIP: Bool
    let vipExpireTime: Date?
    let rawDeviceStatus: String
    let userId: Int
    let accessToken: String

    var deviceStatus: DeviceStatus {
        return DeviceStatus(rawValue: rawDeviceStatus) ?? .active
    }

    enum CodingKeys: String, CodingKey {
        case isVIP = "is_vip"
        case vipExpireTime = "vip_expire_time"
        case rawDeviceStatus = "device_status"
        case userId = "user_id"
        case accessToken = "access_token"
    }
}

nonisolated
enum DeviceStatus: String {
    case active
    case kicked
}
