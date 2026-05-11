import SwiftUI

protocol SortOption: CaseIterable, Hashable {
    var displayName: String { get }
}

struct SortDropdownView<T: SortOption>: View {
    @Binding var selectedOption: T
    @Binding var isAscending: Bool
    let options: [T]
    private let height: CGFloat = 32
    private let separatorGap: CGFloat = 14
    private let directionIconSize: CGFloat = 12
    private let directionIconHorizontalInset: CGFloat = 3
    private var directionButtonWidth: CGFloat {
        directionIconSize + max(0, separatorGap - directionIconHorizontalInset) * 2
    }

    init(selectedOption: Binding<T>, isAscending: Binding<Bool>) {
        self._selectedOption = selectedOption
        self._isAscending = isAscending
        self.options = Array(T.allCases)
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: {
                        selectedOption = option
                    }) {
                        Text(option.displayName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedOption.displayName)
                        .font(PulseFont.regular(12))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, separatorGap)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, minHeight: height)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 0.5)
                .padding(.vertical, 6)

            Button(action: {
                isAscending.toggle()
            }) {
                HugeIconImage(isAscending ? .arrowUp01 : .arrowDown01, size: directionIconSize)
                    .foregroundColor(.primary)
                    .frame(width: directionButtonWidth, height: height)
            }
            .buttonStyle(.plain)
            .help(isAscending ? "Sort descending" : "Sort ascending")
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(height: height)
    }
}

extension ProcessSortOption: SortOption {}

#Preview {
    SortDropdownView<ProcessSortOption>(selectedOption: .constant(.name), isAscending: .constant(true))
        .padding()
}
