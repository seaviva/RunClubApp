//
//  RunSummaryView.swift
//  RunClub
//

import SwiftUI

struct RunSummaryView: View {
    let template: RunTemplateType
    let duration: DurationCategory
    let distanceMiles: Double
    let elapsedSeconds: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("RUN SUMMARY").font(RCFont.medium(24))
            HStack(spacing: 24) {
                metric("Template", template.rawValue)
                metric("Duration", duration.displayName)
            }
            HStack(spacing: 24) {
                metric("Time", formattedTime(elapsedSeconds))
                metric("Distance", String(format: "%.2f mi", distanceMiles))
            }
            Spacer()
        }
        .padding(20)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(RCFont.regular(13)).foregroundColor(.secondary)
            Text(value).font(RCFont.semiBold(18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}


