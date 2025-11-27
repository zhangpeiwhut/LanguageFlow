import SwiftUI
import UIKit

struct DictionaryLookupView: UIViewControllerRepresentable {
    let word: String

    func makeUIViewController(context: Context) -> UIViewController {
        return UIReferenceLibraryViewController(term: word)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
