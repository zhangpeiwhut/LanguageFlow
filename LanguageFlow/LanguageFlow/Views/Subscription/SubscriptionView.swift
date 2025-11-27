import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @State private var iapManager = IAPManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Banner
                    if iapManager.isSubscribed {
                        activeSubscriptionBanner
                    }

                    // Subscription Store View
                    subscriptionStoreSection
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("LanguageFlow Pro")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await iapManager.refresh()
            }
        }
    }

    // MARK: - Active Subscription Banner
    private var activeSubscriptionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("已激活 Pro 会员")
                    .font(.headline)
                Text("感谢您的支持，尽情享用完整功能")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(0.1))
        )
    }

    // MARK: - Subscription Store Section
    private var subscriptionStoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择订阅方案")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 4)
            
            SubscriptionStoreView(groupID: SubscriptionGroupID.pro)
                .subscriptionStoreControlStyle(.prominentPicker)
                .subscriptionStorePickerItemBackground(.regularMaterial)
                .storeButton(.visible, for: .restorePurchases)
        }
    }
}

// MARK: - Feature Row
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
