import Foundation

@MainActor
final class GlobalMetricsStore: ObservableObject {
    @Published var metrics: GlobalSystemMetrics?
}
