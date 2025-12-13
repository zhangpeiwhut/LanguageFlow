//
//  Array+Extension.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/14/25.
//

import Foundation

public extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
