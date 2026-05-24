import CoreBluetooth

enum Libre3BLEUUIDs {
    static let dataService = CBUUID(string: "089810cc-ef89-11e9-81b4-2a2ae2dbcce4")
    static let securityService = CBUUID(string: "0898203a-ef89-11e9-81b4-2a2ae2dbcce4")

    static let patchControl = CBUUID(string: "08981338-ef89-11e9-81b4-2a2ae2dbcce4")
    static let patchStatus = CBUUID(string: "08981482-ef89-11e9-81b4-2a2ae2dbcce4")
    static let glucoseData = CBUUID(string: "0898177a-ef89-11e9-81b4-2a2ae2dbcce4")
    static let historicData = CBUUID(string: "0898195a-ef89-11e9-81b4-2a2ae2dbcce4")
    static let clinicalData = CBUUID(string: "08981ab8-ef89-11e9-81b4-2a2ae2dbcce4")
    static let eventLog = CBUUID(string: "08981bee-ef89-11e9-81b4-2a2ae2dbcce4")
    static let factoryData = CBUUID(string: "08981d24-ef89-11e9-81b4-2a2ae2dbcce4")

    static let securityCommandResponse = CBUUID(string: "08982198-ef89-11e9-81b4-2a2ae2dbcce4")
    static let securityChallengeData = CBUUID(string: "089822ce-ef89-11e9-81b4-2a2ae2dbcce4")
    static let securityCertificateData = CBUUID(string: "089823fa-ef89-11e9-81b4-2a2ae2dbcce4")

    static let servicesToDiscover: [CBUUID] = [
        dataService,
        securityService
    ]

    static let securityNotifyOrder: [CBUUID] = [
        securityCommandResponse,
        securityCertificateData,
        securityChallengeData
    ]

    static let dataNotifyOrder: [CBUUID] = [
        patchControl,
        eventLog,
        historicData,
        clinicalData,
        factoryData,
        glucoseData,
        patchStatus
    ]

    static func name(for uuid: CBUUID) -> String {
        switch uuid {
        case dataService: return "Data service"
        case securityService: return "Security service"
        case patchControl: return "Patch control"
        case patchStatus: return "Patch status"
        case glucoseData: return "Glucose data"
        case historicData: return "Historic data"
        case clinicalData: return "Clinical data"
        case eventLog: return "Event log"
        case factoryData: return "Factory data"
        case securityCommandResponse: return "Security command/response"
        case securityChallengeData: return "Security challenge data"
        case securityCertificateData: return "Security certificate data"
        default: return uuid.uuidString
        }
    }
}
