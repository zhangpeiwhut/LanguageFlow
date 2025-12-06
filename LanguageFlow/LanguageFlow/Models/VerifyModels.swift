//
//  VerifyModel.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/6/25.
//

import Foundation

nonisolated
struct VerifyResponse: Codable {
    let code: Int
    let message: String
    let data: VerifyData
}

nonisolated
struct VerifyData: Codable {
    let isVIP: Bool
    let vipExpireTime: Date?
    let boundDevices: [String]
    let kickedDevice: String?

    enum CodingKeys: String, CodingKey {
        case isVIP = "is_vip"
        case vipExpireTime = "vip_expire_time"
        case boundDevices = "bound_devices"
        case kickedDevice = "kicked_device"
    }
}
