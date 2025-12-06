//
//  AuthInterceptor.swift
//  LanguageFlow
//
//  Alamofire 拦截器：自动处理 Token 过期和重试
//

import Foundation
import Alamofire

final class AuthInterceptor: RequestInterceptor {
    private var isRefreshing = false
    private var requestsToRetry: [(RetryResult) -> Void] = []

    // MARK: - RequestAdapter

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
        guard let response = request.task?.response as? HTTPURLResponse,
              response.statusCode == 401 else {
            // 不是 401，不重试
            completion(.doNotRetryWithError(error))
            return
        }

        // 不需要鉴权的接口白名单
        let noAuthPaths = [
            "/auth/register",
            "/info/channels"
        ]
        
        // 如果是不需要鉴权的接口返回 401，说明有其他问题，不重试
        if let path = request.request?.url?.path,
           noAuthPaths.contains(where: { path.contains($0) }) {
            completion(.doNotRetryWithError(error))
            return
        }

        // 将请求加入等待队列
        requestsToRetry.append(completion)

        // 如果已经在刷新 Token，等待即可
        guard !isRefreshing else { return }

        // 开始刷新 Token
        refreshToken { [weak self] success in
            guard let self = self else { return }

            self.isRefreshing = false

            if success {
                // 刷新成功，重试所有等待的请求
                self.requestsToRetry.forEach { $0(.retry) }
            } else {
                // 刷新失败，所有请求都失败
                let error = NSError(
                    domain: "AuthInterceptor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to refresh token"]
                )
                self.requestsToRetry.forEach { $0(.doNotRetryWithError(error)) }
            }

            self.requestsToRetry.removeAll()
        }
    }

    // MARK: - Private Methods

    private func refreshToken(completion: @escaping (Bool) -> Void) {
        isRefreshing = true

        Task {
            do {
                // 强制刷新用户状态，会获取新的 Token
                try await AuthManager.shared.syncUserStatus(force: true)
                print("[Info] Token refreshed successfully")
                completion(true)
            } catch {
                print("[Error] Failed to refresh token: \(error)")
                completion(false)
            }
        }
    }
}
