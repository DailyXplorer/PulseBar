import SwiftUI

protocol SortOption: CaseIterable, Hashable {
    var displayName: String { get }
}

struct SortDropdownView<T: SortOption>: View {
    @Binding var selectedOption: T
    @Binding var isAscending: Bool
    let options: [T]
    
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
                Text(selectedOption.displayName)
                    .font(PulseFont.regular(12))
                .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
            .padding(.leading, 6)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 0.5)
                .padding(.vertical, 4)
            
            Button(action: {
                isAscending.toggle()
            }) {
                HugeIconImage(isAscending ? .arrowUp01 : .arrowDown01, size: 12)
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
            .padding(.trailing, 4)
            .help(isAscending ? "Sort descending" : "Sort ascending")
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .frame(height: 32)
    }
}

extension ProcessSortOption: SortOption {}

#Preview {
    SortDropdownView<ProcessSortOption>(selectedOption: .constant(.name), isAscending: .constant(true))
        .padding()
}
