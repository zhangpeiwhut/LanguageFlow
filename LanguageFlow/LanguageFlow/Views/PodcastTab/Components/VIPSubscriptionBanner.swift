//
//  VIPSubscriptionBanner.swift
//  LanguageFlow
//

import SwiftUI

struct VIPSubscriptionBanner: View {
    @State private var currentPityIndex = 0
    @State private var pityRotationTask: Task<Void, Never>?
    
    private let pityImages = ["pity_1", "pity_2", "pity_3", "pity_4"]
    private let pityMessages = [
        ("解锁全部内容畅听无限", "求求了，买一个吧～"),
        ("开启完整学习体验", "真的很需要你的支持!"),
        ("解锁更多高级功能", "等你好久了~"),
        ("持续更新与维护", "真的还在坚持!")
    ]
    
    var body: some View {
        NavigationLink(destination: SubscriptionView()) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(pityImages[currentPityIndex])
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pityMessages[currentPityIndex].0)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text(pityMessages[currentPityIndex].1)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .glassEffect()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .buttonStyle(.plain)
        .onAppear {
            startPityImageRotation()
        }
        .onDisappear {
            stopPityImageRotation()
        }
    }
    
    private func startPityImageRotation() {
        pityRotationTask?.cancel()
        currentPityIndex = 0
        pityRotationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3秒
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentPityIndex = (currentPityIndex + 1) % pityImages.count
                }
            }
        }
    }
    
    private func stopPityImageRotation() {
        pityRotationTask?.cancel()
        pityRotationTask = nil
    }
}

#Preview {
    VIPSubscriptionBanner()
}
