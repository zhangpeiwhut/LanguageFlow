//
//  ActionButton.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/14/25.
//
import SwiftUI

struct ActionButton: View {
    let imageName: String
    let text: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isEnabled ? Color.primary.opacity(0.15) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}
