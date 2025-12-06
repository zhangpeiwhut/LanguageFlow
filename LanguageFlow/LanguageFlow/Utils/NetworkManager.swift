//
//  NetworkManager.swift
//  LanguageFlow
//
//  统一的网络请求管理器，自动处理 Token 刷新
//

import Foundation
import Alamofire

class NetworkManager {
    static let shared = NetworkManager()

    private let session: Session

    private init() {
        let interceptor = AuthInterceptor()
        session = Session(interceptor: interceptor)
    }

    /// 发起请求（自动处理 Token）
    func request(
        _ convertible: URLConvertible,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        headers: HTTPHeaders? = nil
    ) -> DataRequest {
        return session.request(
            convertible,
            method: method,
            parameters: parameters,
            encoding: encoding,
            headers: headers
        )
    }
}
