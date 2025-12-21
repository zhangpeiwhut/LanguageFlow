import SwiftUI

// MARK: - Toast Position
enum ToastPosition {
    case top
    case center
    case bottom
}

enum ToastDefaults {
    static let iconSize = CGSize(width: 19, height: 19)
}

enum ToastIconSource: Equatable {
    case system
    case asset
}

// MARK: - Toast Model
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String?
    let iconSource: ToastIconSource
    let iconSize: CGSize
    let message: String
    let duration: TimeInterval
    let position: ToastPosition

    init(
        icon: String? = nil,
        iconSource: ToastIconSource = .system,
        iconSize: CGSize = ToastDefaults.iconSize,
        message: String,
        duration: TimeInterval = 2.5,
        position: ToastPosition = .center
    ) {
        self.icon = icon
        self.iconSource = iconSource
        self.iconSize = iconSize
        self.message = message
        self.duration = min(max(0, duration), 10)
        self.position = position
    }
}

// MARK: - Toast Manager
@Observable
class ToastManager {
    static let shared = ToastManager()

    var currentToast: Toast?
    private var workItem: DispatchWorkItem?

    private init() {}

    func show(_ toast: Toast) {
        workItem?.cancel()

        withAnimation(.spring(duration: 0.4)) {
            currentToast = toast
        }

        if toast.duration > 0 {
            let task = DispatchWorkItem { [weak self] in
                withAnimation(.spring(duration: 0.3)) {
                    self?.currentToast = nil
                }
            }
            workItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration, execute: task)
        }
    }

    func show(
        _ message: String,
        icon: String? = nil,
        iconSource: ToastIconSource = .system,
        iconSize: CGSize = ToastDefaults.iconSize,
        duration: TimeInterval = 2.5,
        position: ToastPosition = .center
    ) {
        show(Toast(
            icon: icon,
            iconSource: iconSource,
            iconSize: iconSize,
            message: message,
            duration: duration,
            position: position
        ))
    }

    func dismiss() {
        workItem?.cancel()
        withAnimation(.spring(duration: 0.3)) {
            currentToast = nil
        }
    }
}

// MARK: - Toast View
struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var backgroundColor: Color {
        let base = isDark ? Color.white : Color(white: 0.12)
        return base.opacity(isDark ? 0.9 : 0.7)
    }
    private var foregroundColor: Color { isDark ? Color.black.opacity(0.9) : .white }
    private var shadowColor: Color { Color.black.opacity(isDark ? 0.18 : 0.28) }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = toast.icon {
                Group {
                    if toast.iconSource == .system {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(foregroundColor)
                    } else {
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: toast.iconSize.width, height: toast.iconSize.height)
                .padding(.leading, 14)
            } else {
                Color.clear.frame(width: 14)
            }

            Text(toast.message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Color.clear.frame(width: 14)
        }
        .frame(height: 48)
        .background {
            Capsule()
                .fill(backgroundColor)
        }
        .compositingGroup()
        .shadow(color: shadowColor, radius: 16, y: 8)
        .padding(.horizontal, 24)
        .onTapGesture {
            onDismiss()
        }
    }
}

// MARK: - Transform Modifier for Animation
struct ToastTransformModifier: ViewModifier {
    var yOffset: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
    }
}

// MARK: - Toast Container Modifier
struct ToastContainerModifier: ViewModifier {
    @Bindable var toastManager: ToastManager

    func body(content: Content) -> some View {
        ZStack {
            content
                .environment(toastManager)

            if let toast = toastManager.currentToast {
                let position = toast.position
                VStack {
                    if position != .top { Spacer() }

                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .transition(
                        .modifier(
                            active: ToastTransformModifier(
                                yOffset: position == .top ? -96 : (position == .bottom ? 96 : 0),
                                scale: position == .center ? 0.8 : 0.5,
                                opacity: 0.0
                            ),
                            identity: ToastTransformModifier(yOffset: 0, scale: 1.0, opacity: 1.0)
                        )
                    )
                    .padding(position == .top ? .top : (position == .bottom ? .bottom : .vertical), 8)

                    if position != .bottom { Spacer() }
                }
                .animation(.spring(duration: 0.4), value: toast.id)
                .zIndex(999)
            }
        }
    }
}

extension View {
    func toastContainer(manager: ToastManager) -> some View {
        modifier(ToastContainerModifier(toastManager: manager))
    }
}

// MARK: - Preview
#Preview("Toast Examples") {
    @Previewable @State var toastManager = ToastManager.shared

    VStack(spacing: 20) {
        Button("Show Toast") {
            toastManager.show(
                "会员专享内容",
                icon: "evil",
                iconSource: .asset,
                iconSize: CGSize(width: 24, height: 24)
            )
        }

        Button("Show Success") {
            toastManager.show("操作成功！", icon: "checkmark")
        }

        Button("Show Error") {
            toastManager.show("操作失败，请重试", icon: "xmark")
        }

        Button("Show Info") {
            toastManager.show("这是一条提示信息", icon: "info")
        }

        Button("Show No Icon") {
            toastManager.show("Copied")
        }
    }
    .toastContainer(manager: toastManager)
}
