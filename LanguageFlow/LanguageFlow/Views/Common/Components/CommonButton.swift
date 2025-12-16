//
//  CommonButton.swift
//  Mystery
//
//  Created by zhangpeibj01 on 2/28/25.
//

import SwiftUI

struct CommonButton: View {
    let title: String
    let topColor: Color
    let bottomColor: Color
    let textColor: Color
    let textFont: Font
    let borderColor: Color?
    let borderWidth: CGFloat?
    let absOffsetY: CGFloat
    let height: CGFloat
    let action: (() -> Void)?

    init(
        title: String,
        topColor: Color = .main,
        bottomColor: Color = .main,
        textColor: Color = .white,
        textFont: Font = .system(size: 18, weight: .semibold, design: .rounded),
        borderColor: Color? = nil,
        borderWidth: CGFloat? = nil,
        absOffsetY: CGFloat = 4,
        height: CGFloat = 45,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.textColor = textColor
        self.textFont = textFont
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.absOffsetY = absOffsetY
        self.height = height
        self.action = action
    }

    @State private var isPress = false

    var offsetY: CGFloat {
        isPress ? 0 : -absOffsetY
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .foregroundStyle(bottomColor.opacity(0.7))
                    .frame(height: height)
                    .overlay {
                        if let borderColor, let borderWidth {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(borderColor, lineWidth: borderWidth)
                        }
                    }

                RoundedRectangle(cornerRadius: 16)
                    .foregroundStyle(topColor)
                    .frame(height: height)
                    .overlay {
                        if let borderColor, let borderWidth {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(borderColor, lineWidth: borderWidth)
                        }
                    }
                    .offset(y: offsetY)
                    .overlay {
                        Text(title)
                            .foregroundStyle(textColor)
                            .font(textFont)
                            .offset(y: offsetY)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let isTouchInside = geometry.frame(in: .local).contains(value.location)
                                if isTouchInside {
                                    withAnimation(.spring(.snappy(duration: 0.01))) {
                                        isPress = true
                                    }
                                } else {
                                    withAnimation(.spring(.snappy(duration: 0.01))) {
                                        isPress = false
                                    }
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring(.snappy(duration: 0.01))) {
                                    isPress = false
                                }
                                let isTouchInside = geometry.frame(in: .local).contains(value.location)
                                if isTouchInside {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                        action?()
                                    }
                                }
                            }
                    )
            }
            .frame(height: height)
        }
        .frame(height: height)
    }
}
