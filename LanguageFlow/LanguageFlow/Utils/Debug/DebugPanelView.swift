//
//  DebugPanelView.swift
//  LanguageFlow
//
//  Debug-only configuration panel (e.g., environment switch).
//

#if DEBUG
import SwiftUI

struct DebugPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEnvironment = DebugConfig.environment
    @AppStorage(DebugConfig.recitingDebugEnabledKey) private var recitingDebugEnabled: Bool = DebugConfig.recitingDebugEnabled

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("环境") {
                    Picker("当前环境", selection: $selectedEnvironment) {
                        ForEach(DebugConfig.Environment.allCases, id: \.self) { env in
                            HStack {
                                Text(env.displayName)
                                Spacer()
                                Text(env.baseURL)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(env)
                        }
                    }
                }

                Section("背诵") {
                    Toggle("Reciting Debug", isOn: $recitingDebugEnabled)
                }
            }
            .navigationTitle("Debug 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .onChange(of: selectedEnvironment) { _, newValue in
            applyEnvironment(newValue)
        }
    }

    private func applyEnvironment(_ env: DebugConfig.Environment) {
        guard env != DebugConfig.environment else { return }
        DebugConfig.setEnvironment(env)
    }
}
#endif
