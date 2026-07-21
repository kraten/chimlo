import ChimloCore
import Foundation

enum CapacityLayout {
    static let usageContentHeight: CGFloat = 160
}

struct CapacityReading: Equatable {
    let window: CapacityWindowSnapshot?
    let isApproximate: Bool
    let lastUpdatedAt: Date?

    var remainingPercentage: Double? {
        window?.remainingPercentage
    }

    var isWarning: Bool {
        guard let remainingPercentage else { return false }
        return remainingPercentage <= CapacityPolicy.warningRemainingPercentage
    }

    var isExhausted: Bool {
        remainingPercentage == 0
    }
}
