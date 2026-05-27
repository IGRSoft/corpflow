// SimpleView.swift — canvas-fixture sample View
//
// Fixture for the apple-canvas end-to-end smoke (run-e2e.sh):
//   1. preview-ensurer should auto-add a `#Preview { SimpleView() }` block (A1, A4 paths).
//   2. SnapshotHost should render it to a PNG via ImageRenderer.
//   3. (optional) QA's visual-diff.sh can compare against a bundled design-ref.png.
//
// This file intentionally ships with NO `#Preview` macro — the smoke
// validates the preview-ensurer auto-add path.

import SwiftUI

struct SimpleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Canvas Fixture")
                .font(.title)
            Text("preview-ensurer + apple-canvas end-to-end smoke")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97))
    }
}
