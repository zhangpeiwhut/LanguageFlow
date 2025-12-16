//
//  Color+Extension.swift
//  Mystery
//
//  Created by zhangpeibj01 on 2/27/25.
//

import Foundation
import SwiftUI

extension Color {
    /// 主题色
    static let main = Color(hex: "7E57C2")
    /// 点缀色 - 浅蓝
    static let accent1 = Color(hex: "D1EBF7")
    /// 点缀色 - 深蓝
    static let accent2 = Color(hex: "A3D6EF")
    /// 点缀色 - 深深蓝
    static let accent3 = Color(hex: "1999D7")
    /// 字体色 - 主要文字
    static let title = Color(hex: "272727")
    /// 字体色 - 次要文字
    static let subtitle = Color(hex: "7A7A7A")
    /// 背景色 - 深灰
    static let background1 = Color(hex: "FAFAFA")
    /// 背景色 - 浅浅灰
    static let background2 = Color(hex: "EFEFEF")
    /// 背景色 - 浅灰
    static let background3 = Color(hex: "E5E5E5")
    /// 背景色 - 浅灰2
    static let background4 = Color(hex: "A7AFBB")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static func hex(_ hex: String) -> Color {
        return Color(hex: hex)
    }
}
