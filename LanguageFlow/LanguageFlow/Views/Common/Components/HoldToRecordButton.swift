//
//  HoldToRecordButton.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/14/25.
//
import SwiftUI

struct HoldToRecordButton: View {
    let isRecording: Bool
    let isScoring: Bool
    let onStart: () -> Void
    let onEnd: () -> Void

    @State private var started = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !started && !isRecording && !isScoring {
                    started = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 0.95
                    }
                    onStart()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { _ in
                if started {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                    onEnd()
                }
                started = false
            }

        HStack(spacing: 8) {
            if isRecording {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text("录音中...")
                    .font(.system(size: 15, weight: .semibold))
            } else if isScoring {
                ProgressView()
                    .controlSize(.small)
                Text("AI 打分中...")
                    .font(.system(size: 15, weight: .semibold))
            } else {
                Image("mic")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text("按住录音")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isRecording ? Color.red : (isScoring ? Color.orange : Color.accentColor))
        )
        .scaleEffect(scale)
        .shadow(color: (isRecording ? Color.red : Color.accentColor).opacity(0.25), radius: 6, x: 0, y: 3)
        .gesture(gesture)
        .allowsHitTesting(!isScoring)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: isScoring)
    }
}
