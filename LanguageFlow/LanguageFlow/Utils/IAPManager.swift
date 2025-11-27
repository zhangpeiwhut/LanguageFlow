//
//  IAPManager.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/30/25.
//

import Foundation
import StoreKit
import Observation

enum SubscriptionProductID: String, CaseIterable {
    case monthly = "lf.pro.monthly"
    case yearly  = "lf.pro.yearly"
}

/// Replace with your App Store Connect subscription group identifier.
enum SubscriptionGroupID {
    static let pro = "21845863"
}

enum IAPError: LocalizedError {
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return "无法验证购买收据，请稍后重试。"
        }
    }
}

@Observable
final class IAPManager {
    static let shared = IAPManager()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isSubscribed: Bool = false
    var errorMessage: String?
    var isLoading: Bool = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await observeTransactionUpdates() }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await Product.products(for: SubscriptionProductID.allCases.map(\.rawValue))
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handle(transaction: transaction)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var activeProducts: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  isManagedSubscription(transaction.productID) else {
                continue
            }
            activeProducts.insert(transaction.productID)
        }
        purchasedProductIDs = activeProducts
        isSubscribed = !activeProducts.isEmpty
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                await handle(transaction: transaction)
            } catch {
                continue
            }
        }
    }

    private func handle(transaction: Transaction) async {
        if isManagedSubscription(transaction.productID) {
            purchasedProductIDs.insert(transaction.productID)
            isSubscribed = true
        }
        await transaction.finish()
    }

    private func isManagedSubscription(_ productID: String) -> Bool {
        SubscriptionProductID.allCases.contains(where: { $0.rawValue == productID })
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }
}
