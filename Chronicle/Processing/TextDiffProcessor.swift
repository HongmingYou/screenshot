import Foundation

/// Computes a similarity score between two OCR results using line-level Jaccard similarity.
/// Line-based (rather than word-based) works better for screen content because:
///   • OCR outputs one line per UI element — lines are natural "atoms" of change.
///   • CJK text doesn't have word delimiters, but line breaks are reliable.
struct TextDiffProcessor {

    /// Returns a value in [0, 1]. 1.0 = identical, 0.0 = nothing in common.
    func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }

        let linesA = lineSet(from: a)
        let linesB = lineSet(from: b)

        guard !linesA.isEmpty || !linesB.isEmpty else { return 1.0 }
        guard !linesA.isEmpty, !linesB.isEmpty else { return 0.0 }

        let intersection = Double(linesA.intersection(linesB).count)
        let union        = Double(linesA.union(linesB).count)

        return union > 0 ? intersection / union : 0.0
    }

    private func lineSet(from text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}
