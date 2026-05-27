// AmbiguousMultiView.swift — preview-ensurer fixture
//
// Scenario: file contains 3 top-level View structs, no disambiguating `--view`.
// Expected outcome: preview-ensurer records `ambiguous_view_target` and skips.
//                   action="skipped", reason="ambiguous_view_target".
//                   No file mutation.

import SwiftUI

struct HeaderView: View {
    var body: some View {
        Text("Header")
    }
}

struct BodyView: View {
    var body: some View {
        Text("Body")
    }
}

struct FooterView: View {
    var body: some View {
        Text("Footer")
    }
}
