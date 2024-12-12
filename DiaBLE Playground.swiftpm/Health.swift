import HealthKit


// TODO: async / await, Observers


class HealthKit: Logging {

    enum DataType: CaseIterable, CustomStringConvertible {
        case glucose
        case insulin
        case carbs

        var description: String {
            switch self {
            case .glucose: "glucose"
            case .insulin: "insulin"
            case .carbs:   "carbs"
            }
        }
        var quantityType: HKQuantityType {
            switch self {
            case .glucose: HKQuantityType(.bloodGlucose)
            case .insulin: HKQuantityType(.insulinDelivery)
            case .carbs:   HKQuantityType(.dietaryCarbohydrates)
            }
        }
    }

    var dataTypes: Set<HKQuantityType> { Set(DataType.allCases.map(\.quantityType)) }

    var store: HKHealthStore?
    var glucoseUnit = HKUnit(from: "mg/dl")
    var lastDate: Date?

    var main: MainDelegate!

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            store = HKHealthStore()
        }
    }

    func requestAuthorization() async {
        do {
            // FIXME: *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'NSHealthUpdateUsageDescription must be set in the app's Info.plist in order to request write authorization for the following types: HKQuantityTypeIdentifierBloodGlucose, HKQuantityTypeIdentifierDietaryCarbohydrates, HKQuantityTypeIdentifierInsulinDelivery'
            // try await store?.requestAuthorization(toShare: dataTypes, read: dataTypes)
            throw HKError(.errorHealthDataUnavailable)
        } catch {
            log("HealthKit: error while requesting authorization for \(DataType.allCases) quantity types: \(error.localizedDescription)")
        }
    }

    var isAuthorized: Bool {
        var statuses = [DataType: HKAuthorizationStatus]()
        for type in DataType.allCases {
            if let status = store?.authorizationStatus(for: type.quantityType) {
                statuses[type] = status
            }
        }
        debugLog("HealthKit: authorization statuses: \(statuses.map { "\($0.key): \(["not determined", "denied", "authorized"][$0.value.rawValue])" }.joined(separator: ", "))")
        return statuses[.glucose] == .sharingAuthorized
    }

    func getAuthorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        do {
            let requestStatus = try await store?.statusForAuthorizationRequest(toShare: dataTypes, read: dataTypes) ?? .unknown
            log("HealthKit: authorization request status for \(DataType.allCases) quantity types: request status: \(requestStatus)")
            return requestStatus
        } catch {
            log("HealthKit: error while requesting authorization status for \(DataType.allCases) quantity types: \(error.localizedDescription)")
            return .unknown
        }
    }

    func write(_ glucoseData: [Glucose]) async {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        let samples = glucoseData.map {
            HKQuantitySample(
                type: glucoseType,
                quantity: HKQuantity(unit: glucoseUnit, doubleValue: Double($0.value)),
                start: $0.date,
                end: $0.date,
                metadata: nil)
        }
        do {
            try await store?.save(samples)
            lastDate = samples.last?.endDate
        } catch {
            log("HealthKit: error while saving: \(error.localizedDescription)")
        }
    }


    func read(handler: (([Glucose]) -> Void)? = nil) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: glucoseType, predicate: nil, limit: 12 * 8, sortDescriptors: [sortDescriptor]) {
            [self] query, results, error in
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
                let values = results.enumerated().map {
                    Glucose(
                        Int($0.1.quantity.doubleValue(for: self.glucoseUnit)),
                        id: $0.0,
                        date: $0.1.endDate,
                        source: $0.1.sourceRevision.source.name + " " + $0.1.sourceRevision.source.bundleIdentifier
                    )
                }
                Task { @MainActor in
                    main.history.storedValues = values
                    handler?(values)
                }
            }
        }
        store?.execute(query)
    }
}
