//
//  PulseFont.swift
//  PulseBar
//

import SwiftUI
import AppKit

enum PulseFont {
    private static let telegrafName = "Telegraf-Regular"
    private static let hasTelegraf = NSFont(name: telegrafName, size: 12) != nil

    static func regular(_ size: CGFloat) -> Font {
        base(size)
    }

    static func medium(_ size: CGFloat) -> Font {
        base(size).weight(.medium)
    }

    static func semibold(_ size: CGFloat) -> Font {
        base(size).weight(.semibold)
    }

    private static func base(_ size: CGFloat) -> Font {
        hasTelegraf ? .custom(telegrafName, size: size) : .system(size: size)
    }
}
