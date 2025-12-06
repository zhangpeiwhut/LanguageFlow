//
//  IAPManager.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/30/25.
//

import Foundation
import StoreKit
import Observation
import Alamofire
import UIKit

@Observable
final class IAPManager {
    static let shared = IAPManager()

    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    var isLoading: Bool = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private let baseURL = "https://elegantfish.online"

    init() {
        updatesTask = Task { await observeTransactionUpdates() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await loadProducts()
        try? await AuthManager.shared.syncUserStatus(force: true)
    }

    func loadProducts() async {
        isLoading = true
        do {
            let fetched = try await Product.products(for: SubscriptionProductID.allCases.map(\.rawValue))
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            print("[error] \(error.localizedDescription)")
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let jwsToken = verification.jwsRepresentation
                let transaction = try checkVerified(verification)
                try await verifyPurchaseWithServer(
                    jwsToken: jwsToken,
                    transaction: transaction,
                    eventType: "purchase"
                )
                await transaction.finish()
                try await AuthManager.shared.syncUserStatus(force: true)
                print("[Info] User purchased")
            case .userCancelled:
                print("[Info] User cancelled purchase")
            case .pending:
                print("[Info] Purchase pending approval")
            @unknown default:
                break
            }
        } catch {
            print("[error] \(error.localizedDescription)")
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync() // 同步AppStore状态
            var restored = false
            for await result in Transaction.currentEntitlements {
                do {
                    let jwsToken = result.jwsRepresentation
                    let transaction = try checkVerified(result)
                    try await verifyPurchaseWithServer(
                        jwsToken: jwsToken,
                        transaction: transaction,
                        eventType: "restore"
                    )
                    await transaction.finish()
                    restored = true
                    print("[Info] User restored")
                    try await AuthManager.shared.syncUserStatus(force: true)
                } catch {
                    print("[error] Failed to restore transaction: \(error)")
                    continue
                }
            }
            if !restored {
                print("[Info] \(IAPError.nothingToRestore.localizedDescription)")
            }
        } catch {
            print("[error] \(error.localizedDescription)")
        }
    }

    private func verifyPurchaseWithServer(
        jwsToken: String,
        transaction: Transaction,
        eventType: String
    ) async throws {
        let parameters: [String: Any] = [
            "jws_token": jwsToken,
            "device_name": UIDevice.current.name,
            "event_type": eventType
        ]

        let verifyResponse = try await NetworkManager.shared.request(
            "\(baseURL)/payment/verify",
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default
        )
        .validate()
        .serializingDecodable(VerifyResponse.self, decoder: Self.millisecondsDecoder)
        .value

        print("[Info] Purchase verified: isVIP=\(verifyResponse.data.isVIP)")

        if let kickedDevice = verifyResponse.data.kickedDevice {
            print("[Info] Device kicked: \(kickedDevice)")
        }
    }

    /// 监听交易更新（自动续费、退款等）
    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let jwsToken = result.jwsRepresentation
                let transaction = try checkVerified(result)
                // 自动处理续费
                try await verifyPurchaseWithServer(
                    jwsToken: jwsToken,
                    transaction: transaction,
                    eventType: "renew"
                )
                await transaction.finish()
                // 强制刷新会员状态
                try await AuthManager.shared.syncUserStatus(force: true)
            } catch {
                print("[error] Transaction update failed: \(error)")
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }

    private static var millisecondsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

// MARK: - Related
enum SubscriptionProductID: String, CaseIterable {
    case monthly = "lf.pro.monthly"
    case yearly  = "lf.pro.yearly"
}

enum SubscriptionGroupID {
    static let pro = "21845863"
}

enum IAPError: LocalizedError {
    case unverifiedTransaction
    case serverVerificationFailed
    case missingJWS
    case nothingToRestore

    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            return "无法验证购买收据，请稍后重试。"
        case .serverVerificationFailed:
            return "服务器验证失败，请稍后重试。"
        case .missingJWS:
            return "缺少凭证信息。"
        case .nothingToRestore:
            return "没有可恢复的购买记录。"
        }
    }
}
