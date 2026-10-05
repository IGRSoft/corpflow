// SimpleView.swift — preview-ensurer fixture
//
// Scenario: plain `struct: View` with no parameters and no `#Preview`.
// Expected outcome: preview-ensurer auto-adds `#Preview { SimpleView() }`.
//                   action="added", mock_strategy="concrete-init".

import SwiftUI

struct SimpleView: View {
    var body: some View {
        Text("Hello")
    }
}
