//
//  AuthInterceptor.swift
//  LanguageFlow
//
//  Alamofire 拦截器：自动处理 Token 过期和重试
//

import Foundation
import Alamofire

final class AuthInterceptor: RequestInterceptor {
    private let refreshState = TokenRefreshState()

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
        var urlRequest = urlRequest

        // 不需要鉴权的接口白名单
        let noAuthPaths = [
            "/auth/register",
            "/info/channels"
        ]
        
        // 如果路径在白名单中，不需要添加 Token
        if let path = urlRequest.url?.path,
           noAuthPaths.contains(where: { path.contains($0) }) {
            completion(.success(urlRequest))
            return
        }

        // 添加 Token 到 Header
        if let token = KeychainManager.getToken() {
            urlRequest.headers.add(.authorization(bearerToken: token))
        }

        completion(.success(urlRequest))
    }

    // MARK: - RequestRetrier

    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        guard let response = request.task?.response as? HTTPURLResponse else {
            completion(.doNotRetryWithError(error))
            return
        }

        // 不需要鉴权的接口白名单
        let noAuthPaths = [
            "/auth/register",
            "/info/channels"
        ]

        let path = request.request?.url?.path ?? ""
        let isNoAuthPath = noAuthPaths.contains(where: { path.contains($0) })

        // 如果是不需要鉴权的接口，不处理
        if isNoAuthPath {
            completion(.doNotRetryWithError(error))
            return
        }

        // 处理 401: Token 过期，刷新后重试
        if response.statusCode == 401 {
            Task {
                let shouldStartRefresh = await refreshState.addRequestToRetry(completion)

                if shouldStartRefresh {
                    await refreshToken()
                }
            }
            return
        }

        // 处理 403: VIP 过期或设备被踢，刷新用户状态但不重试
        if response.statusCode == 403 {
            print("[Info] 403 Forbidden detected")

            // 立即返回错误，不阻塞请求
            completion(.doNotRetryWithError(error))

            // 后台异步刷新状态（仅在当前认为是 VIP 时，检查是否过期）
            if AuthManager.shared.isVIP {
                Task {
                    print("[Info] Current user is VIP, refreshing status to check expiration...")
                    try? await AuthManager.shared.syncUserStatus(force: true)
                }
            } else {
                print("[Info] Current user is not VIP, skipping status refresh")
            }

            return
        }

        // 其他错误，不重试
        completion(.doNotRetryWithError(error))
    }

    // MARK: - Private Methods

    private func refreshToken() async {
        do {
            // 强制刷新用户状态，会获取新的 Token
            try await AuthManager.shared.syncUserStatus(force: true)
            print("[Info] Token refreshed successfully")
            
            // 通知所有等待的请求重试
            let requests = await refreshState.completeRefresh(success: true)
            requests.forEach { $0(.retry) }
        } catch {
            print("[Error] Failed to refresh token: \(error)")
            
            // 通知所有等待的请求失败
            let requests = await refreshState.completeRefresh(success: false)
            let error = NSError(
                domain: "AuthInterceptor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to refresh token"]
            )
            requests.forEach { $0(.doNotRetryWithError(error)) }
        }
    }
}

actor TokenRefreshState {
    private var isRefreshing = false
    private var requestsToRetry: [(RetryResult) -> Void] = []

    func addRequestToRetry(_ completion: @escaping (RetryResult) -> Void) -> Bool {
        requestsToRetry.append(completion)
        let shouldStartRefresh = !isRefreshing
        if shouldStartRefresh {
            isRefreshing = true
        }
        return shouldStartRefresh
    }

    func completeRefresh(success: Bool) -> [(RetryResult) -> Void] {
        isRefreshing = false
        let requests = requestsToRetry
        requestsToRetry.removeAll()
        return requests
    }
}
