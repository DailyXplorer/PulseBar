//
//  HugeIconImage.swift
//  PulseBar
//

import SwiftUI

enum HugeIcon: String {
    case menuBarDashboard = "MenuBarDashboardIcon"
    case dashboardSpeed01 = "DashboardSpeed01Icon"
    case refresh = "RefreshIcon"
    case power = "PowerIcon"
    case search01 = "Search01Icon"
    case cancelCircle = "CancelCircleIcon"
    case stopCircle = "StopCircleIcon"
    case arrowUp01 = "ArrowUp01Icon"
    case arrowDown01 = "ArrowDown01Icon"
    case cpu = "CpuIcon"
    case memoryStick = "MemoryStickIcon"
}

struct HugeIconImage: View {
    let icon: HugeIcon
    let size: CGFloat

    init(_ icon: HugeIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
