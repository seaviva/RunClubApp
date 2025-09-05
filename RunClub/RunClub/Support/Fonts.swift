//
//  Fonts.swift
//  RunClub
//
//  Created by Assistant on 8/19/25.
//

import SwiftUI

enum RCFont {
    static func regular(_ size: CGFloat) -> Font { .custom("IBMPlexSans-Regular", size: size) }
    static func thin(_ size: CGFloat) -> Font { .custom("IBMPlexSans-Thin", size: size) }
    static func extraLight(_ size: CGFloat) -> Font { .custom("IBMPlexSans-ExtraLight", size: size) }
    static func light(_ size: CGFloat) -> Font { .custom("IBMPlexSans-Light", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("IBMPlexSans-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("IBMPlexSans-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("IBMPlexSans-Bold", size: size) }
}


