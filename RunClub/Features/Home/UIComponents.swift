//
//  UIComponents.swift
//  RunClub
//

import SwiftUI

// Reusable duration wheel used by DurationPickerSheet
struct DurationWheel: View {
    @Binding var selection: Int
    var values: [Int] = Array(stride(from: 20, through: 120, by: 5))

    var body: some View {
        ZStack {
            NumberWheelPicker(selection: $selection,
                               values: values,
                               rowHeight: 60,
                               fontSize: 28,
                               textColor: UIColor.white)
        }
        .frame(height: 300)
    }
}

// Simple flow layout for left-aligned wrapping used by filter chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var runSpacing: CGFloat = 6

    init(spacing: CGFloat = 6, runSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.runSpacing = runSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let additional = (currentWidth == 0 ? size.width : spacing + size.width)
            if currentWidth + additional > maxWidth {
                totalHeight += rowHeight + runSpacing
                currentWidth = size.width
                rowHeight = size.height
            } else {
                currentWidth += additional
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        let width = maxWidth.isFinite ? maxWidth : currentWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let neededWidth = (x == bounds.minX ? size.width : spacing + size.width)
            if x + neededWidth > bounds.maxX {
                x = bounds.minX
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            let placeX = (x == bounds.minX ? x : x + spacing)
            sub.place(at: CGPoint(x: placeX, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x = placeX + size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// Reusable filter chip used by filters UI
struct FilterChip: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button(action: { isSelected.toggle() }) {
            Text(title)
                .font(RCFont.medium(15))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 40, alignment: .center)
                .background(isSelected ? Color.white.opacity(0.25) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isSelected ? 0.0 : 0.25), lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}


