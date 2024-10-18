import HealthKit


// TODO: async / await, Observers


class HealthKit: Logging {

    enum DataType: CaseIterable {
        case glucose
        case insulin
        case carbs

        var description: String {
            switch self {
                case .glucose: "Glucose"
                case .insulin: "Insulin"
                case .carbs:   "Carbs"
            }
        }

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .glucose: .bloodGlucose
            case .insulin: .insulinDelivery
            case .carbs:   .dietaryCarbohydrates
            }
        }
        var quantityType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: identifier) }
    }

    var store: HKHealthStore?
    var glucoseUnit = HKUnit(from: "mg/dl")
    var lastDate: Date?

    private var quantityTypes: Set<HKQuantityType> {
        var typeSet: Set<HKQuantityType> = []
        for identifier in DataType.allCases.map(\.identifier) {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                typeSet.insert(type)
            } else {
                log("HealthKit: cannot create \(identifier) quantity type")
            }
        }
        return typeSet
    }

    var main: MainDelegate!


    init() {
        if HKHealthStore.isHealthDataAvailable() {
            store = HKHealthStore()
        }
    }

    func requestAuthorization() async {
        do {
            try await store?.requestAuthorization(toShare: quantityTypes, read: quantityTypes)
        } catch {
            self.log("HealthKit: error while requesting authorization for \(self.quantityTypes) quantity types: \(error.localizedDescription)")
        }
    }

    var isAuthorized: Bool {
        var statuses = [DataType: HKAuthorizationStatus]()
        for type in DataType.allCases {
            if let quantityType = type.quantityType, let status = store?.authorizationStatus(for: quantityType) {
                statuses[type] = status
            }
        }
        debugLog("HealthKit: authorization statuses: \(statuses.map { "\($0.key): \(["not determined", "denied", "authorized"][$0.value.rawValue])" })")
        if let glucoseType = DataType.glucose.quantityType {
            return store?.authorizationStatus(for: glucoseType) == .sharingAuthorized
        } else {
            return false
        }
    }

    func getAuthorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        do {
            let requestStatus = try await store?.statusForAuthorizationRequest(toShare: quantityTypes, read: quantityTypes) ?? .unknown
            log("HealthKit: authorization request status for \(self.quantityTypes) quantity types: \(self.quantityTypes)")
            return requestStatus
        } catch {
            log("HealthKit: error while requesting authorization status for \(self.quantityTypes) quantity types: \(error.localizedDescription)")
            return .unknown
        }
    }

    func write(_ glucoseData: [Glucose]) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        let samples = glucoseData.map {
            HKQuantitySample(type: glucoseType,
                             quantity: HKQuantity(unit: glucoseUnit, doubleValue: Double($0.value)),
                             start: $0.date,
                             end: $0.date,
                             metadata: nil)
        }
        store?.save(samples) { [self] success, error in
            if let error  {
                log("HealthKit: error while saving: \(error.localizedDescription)")
            }
            self.lastDate = samples.last?.endDate
        }
    }


    func read(handler: (([Glucose]) -> Void)? = nil) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            let msg = "HealthKit: error: unable to create glucose quantity type"
            log(msg)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: glucoseType, predicate: nil, limit: 12 * 8, sortDescriptors: [sortDescriptor]) { [self] query, results, error in
            guard let results = results as? [HKQuantitySample] else {
                if let error {
                    log("HealthKit: error: \(error.localizedDescription)")
                } else {
                    log("HealthKit: no records")
                }
                return
            }

            self.lastDate = results.first?.endDate

            if results.count > 0 {
                let values = results.enumerated().map { Glucose(Int($0.1.quantity.doubleValue(for: self.glucoseUnit)), id: $0.0, date: $0.1.endDate, source: $0.1.sourceRevision.source.name + " " + $0.1.sourceRevision.source.bundleIdentifier) }
                Task { @MainActor in
                    main.history.storedValues = values
                    handler?(values)
                }
            }
        }
        store?.execute(query)
    }
}
