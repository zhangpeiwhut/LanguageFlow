//
//  FavoritesView.swift
//  LanguageFlow
//
//  Combined favorites (podcasts + segments) with a single tab and segmented switch.
//

import SwiftUI

struct FavoritesView: View {
    private enum FavoritesTab: String, CaseIterable, Identifiable {
        case podcasts
        case segments

        var id: String { rawValue }
        var label: String {
            switch self {
            case .podcasts: return "整篇"
            case .segments: return "单句"
            }
        }
    }

    @State private var selectedTab: FavoritesTab = .podcasts
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        Group {
                            switch selectedTab {
                            case .podcasts:
                                FavoritePodcastsView(navigationPath: $navigationPath, embeddedInScrollView: false)
                            case .segments:
                                FavoriteSegmentsView(embeddedInScrollView: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    } header: {
                        pickerHeader
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { podcastId in
                PodcastLearningView(podcastId: podcastId)
            }
        }
    }
}

private extension FavoritesView {
    var pickerHeader: some View {
        VStack {
            Picker("收藏类型", selection: $selectedTab) {
                ForEach(FavoritesTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
