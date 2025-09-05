//
//  Buttons.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI

// Primary (Active: white fill, black text; Disabled: white 25% opacity)
struct PrimaryFilledButtonStyle: ButtonStyle {
    private struct Background: View {
        @Environment(\.isEnabled) var isEnabled
        var body: some View {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isEnabled ? 1.0 : 0.25))
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RCFont.semiBold(18))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Background())
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// Primary with custom fill color override (e.g., #00FF77 for Run Complete)
struct PrimaryFilledColorButtonStyle: ButtonStyle {
    var color: Color
    private struct Background: View {
        @Environment(\.isEnabled) var isEnabled
        var color: Color
        var body: some View {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(isEnabled ? 1.0 : 0.4))
        }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RCFont.semiBold(18))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Background(color: color))
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// Secondary (Active: no fill, white text, 1px white border)
struct SecondaryOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RCFont.semiBold(18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, lineWidth: 1)
            )
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// Tertiary (Active: #111111 fill, white text, 1px 5% white border)
struct TertiaryFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RCFont.semiBold(18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Color(red: 0.066, green: 0.066, blue: 0.066))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// Tertiary selectable variant for onboarding pickers
struct SelectableTertiaryButtonStyle: ButtonStyle {
    var isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RCFont.semiBold(18))
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(isSelected ? Color.white : Color(red: 0.066, green: 0.066, blue: 0.066))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}


