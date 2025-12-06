//
//  DevicesManagementView.swift
//  LanguageFlow
//

import SwiftUI
import Alamofire

struct DevicesManagementView: View {
    @State private var devices: [BoundDevice] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAlert = false
    @State private var deviceToUnbind: BoundDevice?

    private let baseURL = "https://elegantfish.online/podcast"

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            } else if devices.isEmpty {
                Section {
                    Text("暂无绑定设备")
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach(devices) { device in
                        DeviceRow(device: device) {
                            deviceToUnbind = device
                            showAlert = true
                        }
                    }
                } header: {
                    Text("已绑定设备 (\(devices.count)/2)")
                } footer: {
                    Text("最多允许 2 台设备同时使用会员。第 3 台设备恢复购买时，最老的设备会被自动解绑。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("设备管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDevices()
        }
        .refreshable {
            await loadDevices()
        }
        .alert("确认解绑", isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("解绑", role: .destructive) {
                if let device = deviceToUnbind {
                    Task {
                        await unbindDevice(device)
                    }
                }
            }
        } message: {
            if let device = deviceToUnbind {
                Text("确定要解绑 \"\(device.deviceName ?? "未知设备")\" 吗？该设备将无法继续使用会员功能。")
            }
        }
    }

    // MARK: - API Calls

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NetworkManager.shared.request(
                "\(baseURL)/user/devices",
                method: .get
            )
            .validate()
            .serializingDecodable(DevicesResponse.self, decoder: Self.millisecondsDecoder)
            .value

            await MainActor.run {
                self.devices = response.data.devices.map { device in
                    BoundDevice(
                        id: device.deviceUUID,
                        deviceUUID: device.deviceUUID,
                        deviceName: device.deviceName,
                        bindTime: device.bindTime,
                        lastActiveTime: device.lastActiveTime,
                        isCurrent: device.isCurrent
                    )
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载失败: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func unbindDevice(_ device: BoundDevice) async {
        do {
            _ = try await NetworkManager.shared.request(
                "\(baseURL)/user/devices/\(device.deviceUUID)",
                method: .delete
            )
            .validate()
            .serializingData()
            .value

            // 刷新列表
            await loadDevices()
        } catch {
            await MainActor.run {
                self.errorMessage = "解绑失败: \(error.localizedDescription)"
            }
        }
    }

    private static var millisecondsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: BoundDevice
    let onUnbind: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 设备图标
            Image(systemName: device.isCurrent ? "iphone.badge.checkmark" : "iphone")
                .font(.title2)
                .foregroundColor(device.isCurrent ? .green : .secondary)
                .frame(width: 40)

            // 设备信息
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.deviceName ?? "未知设备")
                        .font(.headline)

                    if device.isCurrent {
                        Text("当前设备")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green)
                            )
                    }
                }

                Text("绑定时间: \(device.bindTime.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("最后活跃: \(device.lastActiveTime.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 解绑按钮
            if !device.isCurrent {
                Button(action: onUnbind) {
                    Text("解绑")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Models

struct BoundDevice: Identifiable {
    let id: String
    let deviceUUID: String
    let deviceName: String?
    let bindTime: Date
    let lastActiveTime: Date
    let isCurrent: Bool
}

nonisolated
struct DevicesResponse: Codable {
    let code: Int
    let message: String
    let data: DevicesData
}

struct DevicesData: Codable {
    let devices: [DeviceInfo]
}

struct DeviceInfo: Codable {
    let deviceUUID: String
    let deviceName: String?
    let bindTime: Date
    let lastActiveTime: Date
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case deviceUUID = "device_uuid"
        case deviceName = "device_name"
        case bindTime = "bind_time"
        case lastActiveTime = "last_active_time"
        case isCurrent = "is_current"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DevicesManagementView()
    }
}
