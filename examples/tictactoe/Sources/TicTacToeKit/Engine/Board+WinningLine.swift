extension Board {
    /// The indices of the winning line, if the board currently has a winner.
    public func winningLine() -> [Int]? {
        for (a, b, c) in Board.winLines {
            guard let va = (try? cell(a)) ?? nil,
                  let vb = (try? cell(b)) ?? nil,
                  let vc = (try? cell(c)) ?? nil else {
                continue
            }
            if va == vb, va == vc {
                return [a, b, c]
            }
        }
        return nil
    }
}
