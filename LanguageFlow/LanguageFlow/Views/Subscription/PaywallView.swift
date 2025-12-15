//
//  PaywallView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/15/25.
//

import Foundation
import SwiftUI
import StoreKit

struct PaywallView<Header: View, Links: View, Loader: View>: View {
    var isCompact: Bool
    var ids: [String]
    var points: [PaywallPoint]
    @ViewBuilder var header: Header
    @ViewBuilder var links: Links
    @ViewBuilder var loader: Loader
    @State private var isLoaded = false

    var body: some View {
        SubscriptionStoreView(productIDs: ids, marketingContent: {

        })
        .subscriptionStoreControlStyle(CustomSubscriptionStyle(isCompact: isCompact, links: { links }, isLoaded: {
            isLoaded = true
        }))
        .storeButton(.hidden, for: .policies)
        .storeButton(.visible, for: .restorePurchases)
        .animation(.easeInOut(duration: 0.35)) { content in
            content.opacity(isLoaded ? 1 : 0)
        }
        .overlay {
            ZStack {
                if !isLoaded {
                    loader.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: isLoaded)
        }
        .offset(y: 12)
    }
}

fileprivate struct CustomSubscriptionStyle<Links: View>: SubscriptionStoreControlStyle {
    var isCompact: Bool
    @ViewBuilder var links: Links
    var isLoaded: () -> ()
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 25) {
                if #available(iOS 18.0, *) {
                    if isCompact {
                        CompactPickerSubscriptionStoreControlStyle().makeBody(configuration: configuration)
                    } else {
                        PagedProminentPickerSubscriptionStoreControlStyle().makeBody(configuration: configuration)
                    }
                } else {
                    AutomaticSubscriptionStoreControlStyle().makeBody(configuration: configuration)
                }
            }
        }
        .onAppear(perform: isLoaded)
    }
}

struct PaywallPoint: Identifiable {
    var id: String = UUID().uuidString
    var symbol: String
    var symbolTint: Color = .primary
    var content: String
}
