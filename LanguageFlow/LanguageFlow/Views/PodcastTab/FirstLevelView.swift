//
//  ChannelListView.swift
//  LanguageFlow
//

import SwiftUI
import UIKit

struct FirstLevelView: View {
    @State private var filteredChannels: [Channel] = Channel.ChannelKnown.allCases.map { knownChannel in
        Channel(company: "VOA", channel: knownChannel.rawValue)
    }
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            Group {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredChannels) { channel in
                            NavigationLink(destination: SecondLevelView(channel: channel)) {
                                ChannelCardView(channel: channel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("频道")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索频道")
            .onChange(of: searchText) { _, newValue in
                filterChannels(searchText: newValue)
            }
        }
    }

    private func filterChannels(searchText: String) {
        let channels = Channel.ChannelKnown.allCases.map { knownChannel in
            Channel(company: "VOA", channel: knownChannel.rawValue)
        }
        let filtered: [Channel]
        if searchText.isEmpty {
            filtered = channels
        } else {
            filtered = channels.filter { channel in
                let chineseName = channel.chineseName
                return channel.channel.localizedCaseInsensitiveContains(searchText) ||
                       channel.company.localizedCaseInsensitiveContains(searchText) ||
                       chineseName.localizedCaseInsensitiveContains(searchText)
            }
        }
        filteredChannels = filtered
    }
}

// MARK: - Channel Card View
struct ChannelCardView: View {
    let channel: Channel
    private let imageAspectRatio: CGFloat = 900.0 / 672.0
    private let labelHeight: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )

            VStack(spacing: 0) {
                Group {
                    if let image = channel.image {
                        image
                            .resizable()
                            .aspectRatio(imageAspectRatio, contentMode: .fit)
                    } else {
                        Color.gray.opacity(0.2)
                            .aspectRatio(imageAspectRatio, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)

                    Text(channel.chineseName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, minHeight: labelHeight, maxHeight: labelHeight)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }
}

private extension Channel {
    enum ChannelKnown: String, CaseIterable {
        // VOA
        case americasNationalParks = "America's National Parks"
        case americasPresidents = "America's Presidents"
        case americanStories = "American Stories"
        case artsCulture = "Arts & Culture"
        case askATeacher = "Ask a Teacher"
        case earlyLiteracy = "Early Literacy"
        case education = "Education"
        case educationTips = "Education Tips"
        case everydayGrammar = "Everyday Grammar"
        case healthLifestyle = "Health & Lifestyle"
        case scienceTechnology = "Science & Technology"
        case usHistory = "U.S. History"
        case wordsAndTheirStories = "Words and Their Stories"

        var chineseName: String {
            switch self {
            case .americasNationalParks:
                return "美国国家公园"
            case .americasPresidents:
                return "美国总统"
            case .americanStories:
                return "美国故事"
            case .artsCulture:
                return "艺术与文化"
            case .askATeacher:
                return "请教老师"
            case .earlyLiteracy:
                return "儿童素养"
            case .education:
                return "教育"
            case .educationTips:
                return "教育小贴士"
            case .everydayGrammar:
                return "日常语法"
            case .healthLifestyle:
                return "健康与生活方式"
            case .scienceTechnology:
                return "科学与技术"
            case .usHistory:
                return "美国历史"
            case .wordsAndTheirStories:
                return "词汇与故事"
            }
        }
        
        var imageName: String {
            switch self {
            case .americasNationalParks:
                return "americas_national_parks"
            case .americasPresidents:
                return "americas_presidents"
            case .americanStories:
                return "american_stories"
            case .artsCulture:
                return "arts_culture"
            case .askATeacher:
                return "ask_a_teacher"
            case .earlyLiteracy:
                return "early_literacy"
            case .education:
                return "education"
            case .educationTips:
                return "education_tips"
            case .everydayGrammar:
                return "everyday_grammar"
            case .healthLifestyle:
                return "health_lifestyle"
            case .scienceTechnology:
                return "science_technology"
            case .usHistory:
                return "us_history"
            case .wordsAndTheirStories:
                return "words_and_their_stories"
            }
        }
    }
    
    var chineseName: String {
        if let knownChannel = ChannelKnown(rawValue: self.channel) {
            return knownChannel.chineseName
        }
        return self.channel
    }
    
    var image: Image? {
        if let knownChannel = ChannelKnown(rawValue: self.channel) {
            return Image(knownChannel.imageName)
        }
        return nil
    }
}
