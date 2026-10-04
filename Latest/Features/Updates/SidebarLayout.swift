// Fork contributions © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import CoreGraphics

/// The ordered layout is built once per snapshot and shared by keyboard
/// scrolling and pointer targeting. Headers and their trailing gaps retain
/// their measured geometry; hit testing uses O(log n) binary search.
@MainActor
struct SidebarLayout {
  let frames: [CGRect]
  let contentHeight: CGFloat

  init(entries: [AppListSnapshot.Entry]) {
    var frames: [CGRect] = []
    frames.reserveCapacity(entries.count)
    var y: CGFloat = 0
    for entry in entries {
      let isHeader: Bool
      if case .section = entry { isHeader = true } else { isHeader = false }
      let height = isHeader ? VisualMetrics.sectionHeaderHeight : VisualMetrics.appRowHeight
      frames.append(CGRect(x: 0, y: y, width: VisualMetrics.sidebarIdealWidth, height: height))
      y += height + (isHeader ? VisualMetrics.sectionHeaderSpacing : 0)
    }
    self.frames = frames
    contentHeight = y
  }

  func row(at y: CGFloat) -> Int? {
    var lower = 0
    var upper = frames.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if frames[middle].maxY <= y { lower = middle + 1 } else { upper = middle }
    }
    guard frames.indices.contains(lower), y >= frames[lower].minY else { return nil }
    return lower
  }
}
