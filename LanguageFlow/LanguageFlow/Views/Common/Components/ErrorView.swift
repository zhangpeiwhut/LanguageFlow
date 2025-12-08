//
//  ErrorView.swift
//  LanguageFlow
//

import SwiftUI

struct ErrorView: View {
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image("error")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120)

            Text("很抱歉，出故障了")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0x999999))

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text("点击重试")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 36)
        .transition(.identity)
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
