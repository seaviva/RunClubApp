//
//  DurationPickerSheet.swift
//  RunClub
//

import SwiftUI

struct DurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    private let originalMinutes: Int
    let category: DurationCategory
    let onDone: (Int?) -> Void

    init(initialMinutes: Int?, category: DurationCategory, onDone: @escaping (Int?) -> Void) {
        _selection = State(initialValue: initialMinutes ?? 30)
        self.originalMinutes = initialMinutes ?? 30
        self.category = category
        self.onDone = onDone
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                let hasChanges = selection != originalMinutes
                ZStack {
                    Text("SET RUN LENGTH")
                        .font(RCFont.light(15))
                        .foregroundColor(.white)
                    HStack {
                        Button(action: { dismiss() }) {
                            Image("x")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: { onDone(selection); dismiss() }) {
                            Image("check")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                                .opacity(hasChanges ? 1.0 : 0.25)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 0)

                DurationWheel(selection: $selection, values: Array(stride(from: 20, through: 120, by: 5)))
                    .padding(.horizontal, 20)

                Button(action: { selection = originalMinutes }) {
                    Text("RESET")
                        .font(RCFont.medium(15))
                        .foregroundColor(Color.white.opacity(hasChanges ? 1.0 : 0.25))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(100)
                }
                .disabled(!hasChanges)
                .padding(.horizontal, 20)
            }
            .padding(.top, 20)
        }
        .presentationDragIndicator(.hidden)
    }
}


