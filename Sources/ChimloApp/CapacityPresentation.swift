import ChimloCore
import Foundation

enum CapacityLayout {
    static let detailsHeight: CGFloat = 72
    static let detailsSpacing: CGFloat = 8

    static var disclosureHeight: CGFloat {
        detailsHeight + detailsSpacing
    }
}

struct CapacityReading: Equatable {
    let window: CapacityWindowSnapshot?
    let isApproximate: Bool
    let lastUpdatedAt: Date?

    var remainingPercentage: Double? {
        window?.remainingPercentage
    }

    var usedPercentage: Double? {
        window?.usedPercentage
    }

    var isWarning: Bool {
        guard let remainingPercentage else { return false }
        return remainingPercentage <= CapacityPolicy.warningRemainingPercentage
    }

    var isExhausted: Bool {
        remainingPercentage == 0
    }
}
