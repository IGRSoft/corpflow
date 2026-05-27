// SimpleView.swift — preview-ensurer fixture
//
// Scenario: pattern-1 View with no parameters and no `#Preview`.
// Expected outcome: preview-ensurer auto-adds `#Preview { SimpleView() }`.
//                   action="added", mock_strategy="concrete-init".

import SwiftUI

struct SimpleView: View {
    var body: some View {
        Text("Hello")
    }
}
