import Foundation

struct PlateCalculator {
    let availablePlates: [Double]

    init(availablePlates: [Double] = [20, 15, 10, 5, 2.5, 1.25]) {
        self.availablePlates = availablePlates.sorted(by: >)
    }

    func platesPerSide(targetWeight: Double, barWeight: Double = 20) -> [Double] {
        var remaining = max(0, (targetWeight - barWeight) / 2)
        var result: [Double] = []

        for plate in availablePlates {
            while remaining + 0.001 >= plate {
                result.append(plate)
                remaining -= plate
            }
        }

        return result
    }

    func plateCounts(targetWeight: Double, barWeight: Double = 20) -> [Double: Int] {
        Dictionary(grouping: platesPerSide(targetWeight: targetWeight, barWeight: barWeight), by: { $0 }).mapValues(\.count)
    }
}
