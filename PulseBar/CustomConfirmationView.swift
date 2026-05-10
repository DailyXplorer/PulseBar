//
//  CustomConfirmationView.swift
//  PulseBar
//

import SwiftUI

struct CustomConfirmationView: View {
    let title: String
    let message: String
    let destructiveButtonText: String
    let cancelButtonText: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text(title)
                        .font(PulseFont.semibold(16))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(PulseFont.regular(13))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(cancelButtonText) {
                        onCancel()
                    }
                    .keyboardShortcut(.escape)
                    .controlSize(.large)

                    Button(destructiveButtonText) {
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 15)
            .frame(maxWidth: 320)
            .padding(.horizontal, 20)
        }
    }
}
