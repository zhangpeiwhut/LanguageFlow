//
//  LoadingView.swift
//  LanguageFlow
//

import SwiftUI
import Combine

struct LoadingView: View {
    @State private var currentImageIndex = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if currentImageIndex == 0 {
                    Image("loading_1")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120)
                } else {
                    Image("loading_2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120)
                }
            }
            .onReceive(timer) { _ in
                currentImageIndex = (currentImageIndex + 1) % 2
            }

            Text("正在加载...")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0x999999))
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
