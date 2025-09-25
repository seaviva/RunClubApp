//
//  Buttons.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI

// Primary filled button
// Active: black fill, white text, 17 semibold, radius 100, width hugs text + 40 padding
// Disabled: 15% opacity black fill
struct PrimaryFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }
    private struct ButtonBody: View {
        @Environment(\.isEnabled) var isEnabled
        let configuration: Configuration
        var body: some View {
            configuration.label
                .font(RCFont.semiBold(17))
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .frame(height: 60)
                .background((isEnabled ? Color.black : Color.black.opacity(0.15)))
                .cornerRadius(100)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
        }
    }
}

// Primary with custom fill color override (e.g., #00FF77 for Run Complete)
struct PrimaryFilledColorButtonStyle: ButtonStyle {
    var color: Color
    private struct Background: View {
        @Environment(\.isEnabled) var isEnabled
        var color: Color
        var body: some View {
            RoundedRectangle(cornerRadius: 100)
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

// Secondary filled button
// Active: white fill, black text, 17 semibold, radius 100, width hugs text + 40 padding
// Disabled: 20% opacity white fill
struct SecondaryOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }
    private struct ButtonBody: View {
        @Environment(\.isEnabled) var isEnabled
        let configuration: Configuration
        var body: some View {
            configuration.label
                .font(RCFont.semiBold(17))
                .foregroundColor(isEnabled ? .black : Color.black.opacity(0.25))
                .padding(.horizontal, 40)
                .frame(height: 60)
                .background(Color.white)
                .cornerRadius(100)
                .opacity(configuration.isPressed ? 0.95 : 1.0)
        }
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


// Circular icon button (e.g., play/pause). Default diameter 60px.
struct CircularIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 60
    var fillColor: Color = .white
    var iconColor: Color = .black
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(iconColor)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(fillColor)
                    .opacity(configuration.isPressed ? 0.95 : 1.0)
            )
    }
}

struct GhostWhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }
    private struct ButtonBody: View {
        @Environment(\.isEnabled) var isEnabled
        let configuration: Configuration
        var body: some View {
            configuration.label
                .font(RCFont.semiBold(17))
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .frame(height: 60)
                .background(Color.white.opacity(0.10))
                .cornerRadius(100)
                .opacity(configuration.isPressed ? 0.95 : 1.0)
        }
    }
}


