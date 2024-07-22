import Foundation
import CoreBluetooth


// https://github.com/LoopKit/G7SensorKit


// TODO:
// enum G7.SensorType {
//     case g710Day
//     case g710DayAlgo2
//     case g715DayNonDrug
// }


@Observable class DexcomG7: Sensor {

    // com.dexcom.coresdk.transmitterG7.command CmdRequest$Opcode class
    enum Opcode: UInt8 {
        case unknown                    = 0x00

        case batteryStatus              = 0x22
        case stopSession                = 0x28
        case egv                        = 0x4e
        case calibrationBounds          = 0x32
        case calibrate                  = 0x34
        case transmitterVersion         = 0x4a
        case transmitterVersionExtended = 0x52
        case encryptionInfo             = 0x38
        case backfill                   = 0x59
        case diagnosticData             = 0x51
        case bleControl                 = 0xea
        case disconnect                 = 0x09
        // AuthOpCodes
        case txIdChallenge              = 0x01
        case appKeyChallenge            = 0x02
        case challengeReply             = 0x03
        case hashFromDisplay            = 0x04
        case statusReply                = 0x05
        case keepConnectionAlive        = 0x06
        case requestBond                = 0x07
        case requestBondResponse        = 0x08
        case exchangePakePayload        = 0x0a
        case certInfo                   = 0x0b  // keks
        case signChallenge              = 0x0c  // keks

        var data: Data { Data([rawValue]) }
    }


    // Connection:
    // write  3535  01 00
    // write  3535  02 + 8 bytes + 02
    // notify 3535  03 + 16 bytes
    // write  3535  04 + 8 bytes
    // notify 3535  05 01 01
    // enable notifications for 3534
    // write  ....  01 00
    // write  3534  4E
    // notify 3534  4E + 18 bytes
    // write  3534  32
    // notify 3534  32 + 19 bytes       // calibrationBounds
    // write  3534  EA 00
    // notify 3534  EA + 16 bytes
    // write  ....  01 00
    // enable notifications for 3536
    // write  3534  59 + 8 bytes       // backfill startTime-endTime
    // notify 3536  9-byte packets
    // notify 3534  59 + 18 bytes
    // write  3534  51 + 9 bytes       // diagnostic 00 startTime-endTime
    // notify 3536  20-byte packets
    // notify 3534  51 + 16 bytes
    // [...]
    // write  3534  09
    //
    // Pairing:
    // enable notifications for 3535 and 3538
    // write  3535  0A 00
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 00
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  0A 01
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 01
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  0A 02
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 02
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  02 + 8 bytes + 02
    // notify 3535  03 + 16 bytes
    // write  3535  04 + 8 bytes
    // notify 3535  05 01 02
    // write  3535  0B00 + 4 bytes
    // notify 3538  20 * 6 bytes
    // notify 3535  0B0000 + 4 bytes
    // notify 3538  20 * 18 + 12 bytes
    // write  3538  20 * 24 + 14 bytes
    // write  3535  0B01 + 4 bytes
    // notify 3538  20 * 6 bytes
    // notify 3535  0B0001 + 4 bytes
    // notify 3538  20 * 16 + 17/18 bytes // *15+7 when repairing
    // write  3538  20 * 23/22 + 6 bytes  // *21+14 when repairing
    // write  3538  0B02 0000 0000
    // notify 3535  0B00 0200 0000 00
    // write  3538  0C + 16 bytes
    // notify 3538  20 * 3 + 4 bytes
    // notify 3535  0C00 + 16 bytes
    // write  3538  20 * 3 + 4 bytes
    // write  3535  06 + byte
    // notify 3535  06 00
    // write  3535  07
    // notify 3535  07 00
    // notify 3535  08 01
    // enable notifications for 3534
    // write  3534  4A
    // notify 3534  4A00 + 18 bytes    // transmitterVersion
    // write  3534  52
    // notify 3534  5200 + 13 bytes    // transmitterVersionExtended
    // write  3534  EA02 01
    // notify 3534  EA00 01
    // write  3534  EA03 7017 0000
    // notify 3534  EA00 7017 0000
    // [4E 32 EA00 59 51 like for a connection]
    // when repairing:
    // write  3534  38
    // notify 3538  20 * 6 + 12 bytes  // encryptionInfo
    // notify 3534  3800 8400 0000


    // enum G7TxController.TransmitterResponseCode {
    //     case success         = 0
    //     case notPermitted    = 1
    //     case notFound        = 2
    //     case ioError         = 3
    //     case badHandle       = 4
    //     case tryLater        = 5
    //     case outOfMemory     = 6
    //     case noAccess        = 7
    //     case segfault        = 8
    //     case busy            = 9
    //     case badArgument     = 10
    //     case noSpace         = 11
    //     case badRange        = 12
    //     case notImplemented  = 13
    //     case timeout         = 14
    //     case protocolError   = 15
    //     case unexpectedError = 16
    // }


    /// called by Dexcom Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        default:
            break

        }

    }


    // G7TxController.G7CalibrationProcessingStatus
    enum CalibrationProcessingStatus: Int {
        case none
        case factoryCalibrated
        case inProgress
        case completeHigh
        case completeLow
    }


    // TODO: secondary states, enum TxControllerG7.G7CalibrationStatus
    //
    // enum G7TxController.G7AlgorithmState {
    //     case warmupG7TxControllerG7AlgorithmState.WarmupSecondary
    //     case inSessionG7TxControllerG7AlgorithmState.InSessionSecondary
    //     case inSessionInvalidG7TxControllerG7AlgorithmState.InSessionInvalidSecondary
    //     case sessionExpiredG7TxControllerG7AlgorithmState.SessionExpiredSecondary
    //     case sessionFailedG7TxControllerG7AlgorithmState.SessionFailedSecondary
    //     case manuallyStoppedG7TxControllerG7AlgorithmState.ManuallyStoppedSecondary
    //     case none
    //     case deployed
    //     case transmitterFailed
    //     case sivFailed
    //     case sessionFailedOutOfRange
    // }
    //
    // enum G7TxController.G7AlgorithmState.WarmupSecondary {
    //     case sivPassed
    //     case parametersUpdated
    //     case signalProcessing
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.InSessionSecondary {
    //     case low
    //     case lowNoPrediction
    //     case lowNoTrend
    //     case lowNoTrendOrPrediction
    //     case inRange
    //     case inRangeNoPrediction
    //     case inRangeNoTrend
    //     case inRangeNoTrendOrPrediction
    //     case high
    //     case highNoPrediction
    //     case highNoTrend
    //     case highNoTrendOrPrediction
    //     case bgTriggered
    //     case bgTriggeredNoPrediction
    //     case bgTriggeredNoTrend
    //     case bgTriggeredNoTrendOrPrediction
    //     case bgTriggeredLow
    //     case bgTriggeredLowNoPrediction
    //     case bgTriggeredLowNoTrend
    //     case bgTriggeredLowNoTrendOrPrediction
    //     case bgTriggeredHigh
    //     case bgTriggeredHighNoPrediction
    //     case bgTriggeredHighNoTrend
    //     case bgTriggeredHighNoTrendOrPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.InSessionInvalidSecondary {
    //     case invalid
    //     case validPrediction
    //     case validTrend
    //     case validTrendAndPrediction
    //     case bgInvalid
    //     case bgInvalidValidPrediction
    //     case bgInvalidValidTrend
    //     case bgInvalidValidTrendAndPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.SessionExpiredSecondary {
    //     case validEgv
    //     case validEgvNoPrediction
    //     case validEgvNoTrend
    //     case validEgvNoTrendOrPrediction
    //     case invalidEgv
    //     case invalidEgvNoPrediction
    //     case invalidEgvNoTrend
    //     case invalidEgvNoTrendOrPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.SessionFailedSecondary {
    //     case unspecified
    //     case sensorFailure
    //     case algorithmFailure
    //     case unexpectedAlgorithmFailure
    //     case noData
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.ManuallyStoppedSecondary {
    //     case none
    //     case skip
    //     case other
    //     case bestTimingForMe
    //     case inaccurate
    //     case noReadings
    //     case sensorFellOff
    //     case discomfort
    //     case error
    // }

}


@Observable class DexcomONEPlus: Sensor {

    /// called by Dexcom Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        default:
            break

        }

    }

}
