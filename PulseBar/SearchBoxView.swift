//
//  SearchBoxView.swift
//  PulseBar
//
//  Created by Ram Patra on 29/07/2025.
//

import SwiftUI

struct SearchBoxView: View {
    @Binding var searchText: String
    let placeholder: String

    var body: some View {
        HStack {
            HugeIconImage(.search01, size: 12)
                .foregroundColor(.secondary)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(PulseFont.regular(12))

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    HugeIconImage(.cancelCircle, size: 12)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}
