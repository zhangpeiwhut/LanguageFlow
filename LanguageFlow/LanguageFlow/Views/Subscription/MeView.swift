//
//  MeView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/15/25.
//

import Foundation
import SwiftUI

struct MeView: View {
    var body: some View {
        PaywallView(
            isCompact: false,
            ids: ["lf.pro.monthly", "lf.pro.yearly"],
            points: [],
            header: {},
            links: {},
            loader: {}
        )
    }
}
