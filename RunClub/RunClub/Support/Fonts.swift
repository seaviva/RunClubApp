//
//  Fonts.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

enum RCFont {
    // SuisseIntl family mapping. Ensure the PostScript names below match the fonts you added
    // under Resources/Fonts and that those files are listed in Info.plist UIAppFonts.
    static func regular(_ size: CGFloat) -> Font { .custom("SuisseIntl-Regular", size: size) }
    static func thin(_ size: CGFloat) -> Font { .custom("SuisseIntl-Thin", size: size) }
    static func extraLight(_ size: CGFloat) -> Font { .custom("SuisseIntl-ExtraLight", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("SuisseIntl-Light", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("SuisseIntl-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("SuisseIntl-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("SuisseIntl-Bold", size: size) }
}


