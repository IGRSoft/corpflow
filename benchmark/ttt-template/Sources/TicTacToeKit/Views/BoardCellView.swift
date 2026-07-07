import SwiftUI

/// A single Tic-Tac-Toe board cell: shows the played mark (if any) and
/// highlights when part of the winning line.
public struct BoardCellView: View {
    public let mark: Player?
    public let isWinningCell: Bool
    public let action: () -> Void

    public init(mark: Player?, isWinningCell: Bool = false, action: @escaping () -> Void) {
        self.mark = mark
        self.isWinningCell = isWinningCell
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isWinningCell ? Color.yellow.opacity(0.35) : Color.gray.opacity(0.15))
                if let mark {
                    Text(mark.rawValue)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(mark == .x ? Color.blue : Color.red)
                        .transition(.scaleAndFade)
                        .animation(AnimationTokens.cellPlacement, value: mark)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(mark.map { "\($0.rawValue) mark" } ?? "Empty cell")
    }
}

#Preview {
    HStack {
        BoardCellView(mark: .x, isWinningCell: true) {}
        BoardCellView(mark: .o) {}
        BoardCellView(mark: nil) {}
    }
    .padding()
}
