// BindingView.swift — preview-ensurer fixture
//
// Scenario: plain `struct: View` with a `@Binding<String>` parameter and no `#Preview`.
// Expected outcome: preview-ensurer auto-adds:
//                       #Preview { BindingView(text: .constant("")) }
//                   action="added", mock_strategy="binding-constant".

import SwiftUI

struct BindingView: View {
    @Binding var text: String

    var body: some View {
        TextField("Type", text: $text)
    }
}
