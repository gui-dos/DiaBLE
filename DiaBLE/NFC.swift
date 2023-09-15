import Foundation
import AVFoundation    // AudioServicesPlaySystemSound()


struct NFCCommand {
    let code: Int
    var parameters: Data = Data()
    var description: String = ""
}

enum NFCError: LocalizedError {
    case commandNotSupported
    case customCommandError
    case read
    case readBlocks
    case write

    var errorDescription: String? {
        switch self {
        case .commandNotSupported: "command not supported"
        case .customCommandError:  "custom command error"
        case .read:                "read error"
        case .readBlocks:          "reading blocks error"
        case .write:               "write error"
        }
    }
}


extension Sensor {

    var backdoor: Data {
        switch self.type {
        case .libre1:    Data([0xc2, 0xad, 0x75, 0x21])
        default:         Data([0xde, 0xad, 0xbe, 0xef])
        }
    }

    var activationCommand: NFCCommand {
        switch self.type {
        case .libre1:
            NFCCommand(code: 0xA0, parameters: backdoor, description: "activate")
        case .libre3:
            (self as! Libre3).activationNFCCommand
        default:
            NFCCommand(code: 0x00)
        }
    }

    var universalCommand: NFCCommand    { NFCCommand(code: 0xA1, description: "A1 universal prefix") }
    var getPatchInfoCommand: NFCCommand { NFCCommand(code: 0xA1, description: "get patch info") }

    // Libre 1
    var lockCommand: NFCCommand         { NFCCommand(code: 0xA2, parameters: backdoor, description: "lock") }
    var readRawCommand: NFCCommand      { NFCCommand(code: 0xA3, parameters: backdoor, description: "read raw") }
    var unlockCommand: NFCCommand       { NFCCommand(code: 0xA4, parameters: backdoor, description: "unlock") }

    // Libre 2
    // SEE: custom commands C0-C4 in TI RF430FRL15xH Firmware User's Guide
    var readBlockCommand: NFCCommand    { NFCCommand(code: 0xB0, description: "B0 read block") }
    var readBlocksCommand: NFCCommand   { NFCCommand(code: 0xB3, description: "B3 read blocks") }


    enum Subcommand: UInt8, CustomStringConvertible {
        case unlock          = 0x1a    // lets read FRAM in clear and dump further blocks with B0/B3
        case activate        = 0x1b
        case enableStreaming = 0x1e
        case getSessionInfo  = 0x1f    // GEN_SECURITY_CMD_GET_SESSION_INFO
        case unknown0x10     = 0x10    // returns the number of parameters + 3
        case unknown0x1c     = 0x1c
        case unknown0x1d     = 0x1d    // disables Bluetooth
        // Gen2
        case readChallenge   = 0x20    // returns 25 bytes
        case readBlocks      = 0x21
        case readAttribute   = 0x22    // returns 6 bytes ([0]: sensor state)

        var description: String {
            switch self {
            case .unlock:          "unlock"
            case .activate:        "activate"
            case .enableStreaming: "enable BLE streaming"
            case .getSessionInfo:  "get session info"
            case .readChallenge:   "read security challenge"
            case .readBlocks:      "read FRAM blocks"
            case .readAttribute:   "read patch attribute"
            default:               "[unknown: 0x\(rawValue.hex)]"
            }
        }
    }


    /// The customRequestParameters for 0xA1 are built by appending
    /// code + parameters + usefulFunction(uid, code, secret)
    func nfcCommand(_ code: Subcommand, parameters: Data = Data(), secret: UInt16 = 0) -> NFCCommand {

        var parameters =  parameters
        let secret = secret != 0 ? secret : Libre2.secret

        if code.rawValue < 0x20 {
            parameters += Libre2.usefulFunction(id: uid, x: UInt16(code.rawValue), y: secret)
        }

        return NFCCommand(code: 0xA1, parameters: Data([code.rawValue]) + parameters, description: code.description)
    }
}


#if !os(watchOS)

import CoreNFC


enum IS015693Error: Int, CustomStringConvertible {
    case none                   = 0x00
    case commandNotSupported    = 0x01
    case commandNotRecognized   = 0x02
    case optionNotSupported     = 0x03
    case unknown                = 0x0f
    case blockNotAvailable      = 0x10
    case blockAlreadyLocked     = 0x11
    case contentCannotBeChanged = 0x12

    var description: String {
        switch self {
        case .none:                   "none"
        case .commandNotSupported:    "command not supported"
        case .commandNotRecognized:   "command not recognized (e.g. format error)"
        case .optionNotSupported:     "option not supported"
        case .unknown:                "unknown"
        case .blockNotAvailable:      "block not available (out of range, doesn’t exist)"
        case .blockAlreadyLocked:     "block already locked -- can’t be locked again"
        case .contentCannotBeChanged: "block locked -- content cannot be changed"
        }
    }
}


extension Error {
    var iso15693Code: Int {
        if let code = (self as NSError).userInfo[NFCISO15693TagResponseErrorKey] as? Int {
            return code
        } else {
            return 0
        }
    }
    var iso15693Description: String { IS015693Error(rawValue: self.iso15693Code)?.description ?? "[code: 0x\(self.iso15693Code.hex)]" }
}


enum TaskRequest {
    case enableStreaming
    case readFRAM
    case dump
    case activate
}


class NFC: NSObject, NFCTagReaderSessionDelegate, Logging {

    var session: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
    var systemInfo: NFCISO15693SystemInfo!
    var sensor: Sensor!

    // Gen2
    var securityChallenge: Data = Data()
    var authContext: Int = 0
    var sessionInfo: Data = Data()

    var taskRequest: TaskRequest? {
        didSet {
            guard taskRequest != nil else { return }
            startSession()
        }
    }

    var main: MainDelegate!

    var isAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    func startSession() {
        // execute in the .main queue because of publishing changes to main's observables
        session = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        session?.alertMessage = "Hold the top of your iPhone near the Libre sensor until the second longer vibration"
        session?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        log("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
                log("NFC: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        log("NFC: did detect tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan Complete"

        Task {

            var patchInfo: PatchInfo = Data()
            let maxRetries = 5

            for retry in 0 ... maxRetries {

                if retry > 0 {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(retry)...")
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                do {
                    try await session.connect(to: firstTag)
                    connectedTag = tag
                    break
                } catch {
                    if retry >= maxRetries {
                        session.invalidate(errorMessage: "Connection failure: \(error.localizedDescription)")
                        log("NFC: stopped retrying to connect after \(retry) reattempts: \(error.localizedDescription)")
                        return
                    }
                    log("NFC: \(error.localizedDescription)")
                }
            }

            for retry in 0 ... maxRetries {

                AudioServicesPlaySystemSound(1520)    // "pop" vibration

                if retry > 0 {
                    log("NFC: retry # \(retry)...")
                    // try await Task.sleep(nanoseconds: 250_000_000) not needed: too long
                }

                do {
                    if systemInfo == nil {
                        systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                    }
                } catch {
                    log("NFC: error while getting system info: \(error.localizedDescription)")
                }

                do {
                    if patchInfo.count == 0 {
                        patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                    }
                } catch {
                    log("NFC: error while getting patch info: \(error.localizedDescription)")
                }

                if systemInfo != nil && !(patchInfo.count == 0 && retry < maxRetries) {
                    break
                } else if retry >= maxRetries {
                    session.invalidate(errorMessage: "Error while getting system info")
                    log("NFC: stopped retrying to get the system info after \(retry) reattempts")
                    return
                }
            }

            let uid = tag.identifier.hex
            log("NFC: IC identifier: \(uid)")

            // Libre 3: extract the 24-byte patchInfo trimming the leading (A5)+ 00 dummy bytes and verifying the final CRC16
            if patchInfo.count >= 28 && patchInfo[0] == 0xA5 {
                let crc = UInt16(patchInfo.suffix(2))
                let info = Data(patchInfo[patchInfo.count - 26 ... patchInfo.count - 3])
                let computedCrc = info.crc16
                if crc == computedCrc {
                    log("Libre 3: patch info: \(info.hexBytes) (scanned \(patchInfo.hex), CRC: \(crc.hex), computed CRC: \(computedCrc.hex))")
                    patchInfo = info
                }
            }

            let currentSensor = await main.app.sensor
            if currentSensor != nil && currentSensor!.uid == Data(tag.identifier.reversed()) {
                sensor = await main.app.sensor
                sensor.patchInfo = patchInfo
            } else {
                if patchInfo.count == 0 {
                    sensor = Sensor(main: main)
                } else {
                    let sensorType = SensorType(patchInfo: patchInfo)
                    switch sensorType {
                    case .libre3:
                        sensor = Libre3(main: main)
                    case .libre2:
                        sensor = Libre2(main: main)
                    default:
                        sensor = Sensor(main: main)
                    }
                }
                sensor.patchInfo = patchInfo
                DispatchQueue.main.async {
                    self.main.app.sensor = self.sensor
                }
            }

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            var manufacturer = tag.icManufacturerCode.hex
            if manufacturer == "07" {
                manufacturer.append(" (Texas Instruments)")
            } else if manufacturer == "7a" {
                manufacturer.append(" (Abbott Diabetes Care)")
                sensor.type = .libre3
                sensor.securityGeneration = 3 // TODO
            }
            log("NFC: IC manufacturer code: 0x\(manufacturer)")
            debugLog("NFC: IC serial number: \(tag.icSerialNumber.hex)")

            if let sensor = sensor as? Libre3 {
                sensor.parsePatchInfo()
            } else {
                sensor.firmware = tag.identifier[2].hex
                log("NFC: firmware version: \(sensor.firmware)")
            }

            debugLog(String(format: "NFC: IC reference: 0x%X", systemInfo.icReference))
            if systemInfo.applicationFamilyIdentifier != -1 {
                debugLog(String(format: "NFC: application family id (AFI): %d", systemInfo.applicationFamilyIdentifier))
            }
            if systemInfo.dataStorageFormatIdentifier != -1 {
                debugLog(String(format: "NFC: data storage format id: %d", systemInfo.dataStorageFormatIdentifier))
            }

            log(String(format: "NFC: memory size: %d blocks", systemInfo.totalBlocks))
            log(String(format: "NFC: block size: %d", systemInfo.blockSize))

            sensor.uid = Data(tag.identifier.reversed())
            log("NFC: sensor uid: \(sensor.uid.hex)")
            log("NFC: sensor serial number: \(sensor.serial)")

            if sensor.patchInfo.count > 0 {
                log("NFC: patch info: \(sensor.patchInfo.hex)")
                log("NFC: sensor type: \(sensor.type.rawValue)\(sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")")
                log("NFC: sensor security generation [0-3]: \(sensor.securityGeneration)")

                DispatchQueue.main.async {
                    self.settings.patchUid = self.sensor.uid
                    self.settings.patchInfo = self.sensor.patchInfo
                }
            }

            if sensor.type == .libre3 && taskRequest == .none {
                // get the current Libre 3 blePIN and activationTime by sending `A0`
                taskRequest = .activate
            }

            if taskRequest != .none {

                if sensor.securityGeneration > 1 && taskRequest != .activate {
                    await testNFCCommands()
                }

                if sensor.type == .libre2 {
                    try await sensor.execute(nfc: self, taskRequest: taskRequest!)
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }

                if taskRequest == .dump || taskRequest == .activate {

                    var invalidateMessage = ""

                    do {
                        try await execute(taskRequest!)
                    } catch let error as NFCError {
                        if error == .commandNotSupported {
                            let description = error.localizedDescription
                            invalidateMessage = description.prefix(1).uppercased() + description.dropFirst() + " by \(sensor.type)"
                        }
                    }

                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    if sensor.type != .libre3 {
                        sensor.detailFRAM()
                    }

                    taskRequest = .none

                    if invalidateMessage.isEmpty {
                        session.invalidate()
                    } else {
                        session.invalidate(errorMessage: invalidateMessage)
                    }
                    await main.status("\(sensor.type)  +  NFC")
                    return
                }

            }

            var blocks = 43
            if taskRequest == .readFRAM {
                if sensor.type == .libre1 {
                    blocks = 244
                }
            }

            do {

                if sensor.securityGeneration == 2 {
                    securityChallenge = try await send(sensor.nfcCommand(.readChallenge))
                    log("NFC: Gen2 security challenge: \(securityChallenge.hex)")
                }

                let (start, data) = try await sensor.securityGeneration < 2 ?
                read(fromBlock: 0, count: blocks) : readBlocks(from: 0, count: blocks)

                log(data.hexDump(header: "NFC: did read \(data.count / 8) FRAM blocks:", startBlock: start))

                let lastReadingDate = Date()

                // "Publishing changes from background threads is not allowed"
                DispatchQueue.main.async {
                    self.main.app.lastReadingDate = lastReadingDate
                }
                sensor.lastReadingDate = lastReadingDate

                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate()

                sensor.fram = Data(data)

            } catch {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate(errorMessage: "\(error.localizedDescription)")
            }

            if taskRequest == .readFRAM {
                sensor.detailFRAM()
                taskRequest = .none
                return
            }

            await main.parseSensorData(sensor)

            await main.status("\(sensor.type)  +  NFC")

        }

    }


    @discardableResult
    func send(_ cmd: NFCCommand) async throws -> Data {
        var data = Data()
        do {
            debugLog("NFC: sending \(sensor.type) '\(cmd.code.hex)\(cmd.parameters.count == 0 ? "" : " \(cmd.parameters.hex)")' custom command\(cmd.description == "" ? "" : " (\(cmd.description))")")
            let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
            data = Data(output!)
        } catch {
            log("NFC: \(sensor.type) '\(cmd.description) \(cmd.code.hex)\(cmd.parameters.count == 0 ? "" : " \(cmd.parameters.hex)")' custom command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            throw error
        }
        return data
    }


    func read(fromBlock start: Int, count blocks: Int, requesting: Int = 3, retries: Int = 5) async throws -> (Int, Data) {

        var buffer = Data()

        var remaining = blocks
        var requested = requesting
        var retry = 0

        while remaining > 0 && retry <= retries {

            let blockToRead = start + buffer.count / 8

            do {
                let dataArray = try await connectedTag?.readMultipleBlocks(requestFlags: .highDataRate, blockRange: NSRange(blockToRead ... blockToRead + requested - 1))

                for data in dataArray! {
                    buffer += data
                }

                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")

                retry += 1
                if retry <= retries {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(retry)...")
                    try await Task.sleep(nanoseconds: 250_000_000)

                } else {
                    if sensor.securityGeneration < 2 || taskRequest == .none {
                        session?.invalidate(errorMessage: "Error while reading multiple blocks: \(error.localizedDescription.localizedLowercase)")
                    }
                    throw NFCError.read
                }
            }
        }

        return (start, buffer)
    }


    func readBlocks(from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {

        if sensor.securityGeneration < 1 {
            debugLog("readBlocks() B3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()

        var remaining = blocks
        var requested = requesting

        while remaining > 0 {

            let blockToRead = start + buffer.count / 8

            var readCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8), UInt8(requested - 1)]))
            if requested == 1 {
                readCommand = NFCCommand(code: 0xB0, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8)]))
            }

            // FIXME: the Libre 3 replies to 'A1 21' with the error code C1

            if sensor.securityGeneration > 1 {
                if blockToRead <= 255 {
                    readCommand = sensor.nfcCommand(.readBlocks, parameters: Data([UInt8(blockToRead), UInt8(requested - 1)]))
                }
            }

            if buffer.count == 0 { debugLog("NFC: sending '\(readCommand.code.hex) \(readCommand.parameters.hex)' custom command (\(sensor.type) read blocks)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readCommand.code, customRequestParameters: readCommand.parameters)
                let data = Data(output!)

                if sensor.securityGeneration < 2 {
                    buffer += data
                } else {
                    debugLog("'\(readCommand.code.hex) \(readCommand.parameters.hex) \(readCommand.description)' command output (\(data.count) bytes): 0x\(data.hex)")
                    buffer += data.suffix(data.count - 8)    // skip leading 0xA5 dummy bytes
                }
                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log(buffer.hexDump(header: "\(sensor.securityGeneration > 1 ? "`A1 21`" : "B0/B3") command output (\(buffer.count/8) blocks):", startBlock: start))

                if requested == 1 {
                    log("NFC: error while reading block #\(blockToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                } else {
                    log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                }
                throw NFCError.readBlocks
            }
        }

        return (start, buffer)
    }


    // MARK: - Libre 1

    func readRaw(_ address: Int, _ bytes: Int) async throws -> (Int, Data) {

        if sensor.type != .libre1 {
            debugLog("readRaw() A3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()
        var remainingBytes = bytes
        let retries = 5
        var retry = 0

        while remainingBytes > 0 && retry <= retries {

            let addressToRead = address + buffer.count
            let bytesToRead = min(remainingBytes, 24)

            var remainingWords = remainingBytes / 2
            if remainingBytes % 2 == 1 || ( remainingBytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
            let wordsToRead = min(remainingWords, 12)   // real limit is 15

            let readRawCommand = NFCCommand(code: 0xA3, parameters: sensor.backdoor + [UInt8(addressToRead & 0xFF), UInt8(addressToRead >> 8), UInt8(wordsToRead)])

            if buffer.count == 0 { debugLog("NFC: sending '\(readRawCommand.code.hex) \(readRawCommand.parameters.hex)' custom command (\(sensor.type) read raw)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readRawCommand.code, customRequestParameters: readRawCommand.parameters)
                var data = Data(output!)

                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - bytesToRead == 1 { data = data.subdata(in: 0 ..< data.count - 1) }

                buffer += data
                remainingBytes -= data.count

            } catch {
                debugLog("NFC: error while reading \(wordsToRead) words at raw memory 0x\(addressToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")

                retry += 1
                if retry <= retries {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(retry)...")
                    try await Task.sleep(nanoseconds: 250_000_000)
                } else {
                    throw NFCError.customCommandError
                }
            }
        }

        return (address, buffer)

    }


    func execute(_ taskRequest: TaskRequest) async throws {

        switch taskRequest {


        case .dump:

            // Libre 1 memory layout:
            // config: 0x1A00, 64    (sensor UID and calibration info)
            // sram:   0x1C00, 512
            // rom:    0x4400 - 0x5FFF
            // fram lock table: 0xF840, 32
            // fram:   0xF860, 1952

            do {
                var (address, data) = try await readRaw(0x1A00, 64)
                log(data.hexDump(header: "Config RAM (patch UID at 0x1A08):", address: address))
                (address, data) = try await readRaw(0x1C00, 512)
                log(data.hexDump(header: "SRAM:", address: address))
                if sensor.type == .libre1 {
                    (address, data) = try await readRaw(0xFFAC, 36)
                    log(data.hexDump(header: "Patch table for A0-A4 E0-E2 commands:", address: address))
                    (address, data) = try await readRaw(0xF860, 244 * 8)
                    log(data.hexDump(header: "FRAM:", address: address))
                }
            } catch {}

            do {
                let (start, data) = try await read(fromBlock: 0, count: 43 + (sensor.type == .libre1 ? 201 : 0))
                log(data.hexDump(header: "ISO 15693 FRAM blocks:", startBlock: start))
                sensor.fram = Data(data)
                if sensor.encryptedFram.count > 0 && sensor.fram.count >= 344 {
                    log("\(sensor.fram.hexDump(header: "Decrypted FRAM:", startBlock: 0))")
                }
            } catch {
            }

            /// count is limited to 89 with an encrypted sensor (header as first 3 blocks);
            /// after sending the A1 1A subcommand the FRAM is decrypted in-place
            /// and mirrored in the last 43 blocks of 89 but the max count becomes 1252
            var count = sensor.encryptedFram.count > 0 ? 89 : 1252
            if sensor.securityGeneration > 1 { count = 43 }

            let command = sensor.securityGeneration > 1 ? "A1 21" : "B0/B3"

            do {

                let (start, data) = try await readBlocks(from: 0, count: count)

                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

                let blocks = data.count / 8

                log(data.hexDump(header: "\'\(command)' command output (\(blocks) blocks):", startBlock: start))

                // await main actor
                if settings.userLevel > .basic {
                    let bytes = min(89 * 8 + 34 + 10, data.count)
                    var offset = 0
                    var i = offset + 2
                    while offset < bytes - 3 && i < bytes - 1 {
                        if UInt16(data[offset ... offset + 1]) == data[offset + 2 ... i + 1].crc16 {
                            log("CRC matches for \(i - offset + 2) bytes at #\((offset / 8).hex) [\(offset + 2)...\(i + 1)] \(data[offset ... offset + 1].hex) = \(data[offset + 2 ... i + 1].crc16.hex)\n\(data[offset ... i + 1].hexDump(header: "\(libre2DumpMap[offset]?.1 ?? "[???]"):", address: 0))")
                            offset = i + 2
                            i = offset
                        }
                        i += 2
                    }
                }

            } catch {
                log("NFC: 'read blocks \(command)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            }


        case .activate:

            if sensor.type == .libre2 || sensor.securityGeneration == 2 {
                log("Activating a \(sensor.type) is not supported anymore")
                throw NFCError.commandNotSupported
            }

            do {

                var output = try await send(sensor.activationCommand)
                log("NFC: after trying to activate received \(output.hex) for the patch info \(sensor.patchInfo.hex)")

                if sensor.type == .libre3 {
                    // output = "A5002BC7291932189F36B26CD01E306209F0".bytes  // TEST
                    output = Data(output.drop(while: { $0 == 0xA5 }))

                    if output[0] == 0x01 && output.count == 2 {
                        log("NFC: Libre 3 activation error: 0x\(output.hex)")
                        // getting 0x01b0 on an expired sensor
                        // getting error 0xc2 when altering crc16
                        // getting error 0xc1 when omitting crc16
                    }

                    if output[0] == 0x00 && output.count == 17 {

                        // i.e. 00A5002BC7291932189F36B26CD01E306209F0 ->
                        // BD_Addr = 2B C7 29 19 32 18 (18:32:19:29:C7:2B)
                        // BLE_Key(BLE_Pin) = 9F36B26C
                        // A_UTC = 1647320784 (0xD01E3062)
                        // APP_CRC16 = 09 F0

                        let activationResponse = Libre3.ActivationResponse(
                            bdAddress: Data(output[1 ..< 7].reversed()),
                            BLE_Pin:   output.subdata(in: 7 ..< 11),
                            activationTime: UInt32(output.subdata(in: 11 ..< 15))
                        )
                        let crc = UInt16(output[15 ... 16])
                        let computedCrc = output[1 ... 14].crc16
                        log("NFC: Libre 3 activation response: \(activationResponse), BLE address: \(activationResponse.bdAddress.hexAddress), BLE PIN: \(activationResponse.BLE_Pin.hex), activation time: \(Date(timeIntervalSince1970: Double(activationResponse.activationTime))), CRC: \(crc.hex), computed CRC: \(computedCrc.hex)")

                        // TODO
                        sensor.transmitter?.macAddress = activationResponse.bdAddress
                        (sensor as! Libre3).blePIN = activationResponse.BLE_Pin
                        sensor.activationTime = activationResponse.activationTime
                        sensor.lastReadingDate = Date()
                        sensor.age = Int(Date().timeIntervalSince(Date(timeIntervalSince1970: Double(sensor.activationTime)))) / 60
                    }
                }

            } catch {

                // TODO: manage errors and verify integrity

            }

            if sensor.type != .libre3 {
                let (_, data) = try await read(fromBlock: 0, count: 43)
                sensor.fram = Data(data)
            }


        default:
            break

        }

    }


    func testNFCCommands() async {

        var commands: [NFCCommand] = [sensor.nfcCommand(.readAttribute),
                                      sensor.nfcCommand(.readChallenge)
        ]

        if settings.userLevel > .basic {

            for c in 0xA0 ... 0xDF {
                commands.append(NFCCommand(code: c, parameters: Data(), description: c.hex))
            }

            // Gen2 supported commands: A1, B1, B2, B4

            // Libre 3:
            // getting 28 bytes from A1: dummy `a5 00` + 24-byte PatchInfo + CRC
            // getting 0xC1 error from A0, A1 20-22, A8, A9, C8, C9  (A0 and A8 activate a sensor)
            // getting 64 0xA5 bytes from A2-A7, AB-C7, CA-DF
            // getting 22 bytes from AA: 44 4f 43 34 32 37 31 35 2d 31 30 31 11 26 20 12 09 00 80 67 73 e0
            //                          (leading `DOC42715-101` and final CRC)
            // getting zeros from standard read command 0x23

        }

        if sensor.type == .libre3 {
            do {
                let aa = try await send(NFCCommand(code: 0xAA))
                log("NFC: Libre 3 `AA` command output: \(aa.hexBytes), CRC: \(Data(aa.suffix(2).reversed()).hex), computed CRC: \(aa.prefix(aa.count-2).crc16.hex), string: \"\(aa.string)\"")
                let params = "0102030405060708090A0B0C0D0E0F10".bytes
                for c in [0xA9, 0xC8, 0xC9] {
                    for p in 1 ... 16 {
                        commands.append(NFCCommand(code: c, parameters: params.prefix(p), description: "\(c.hex) \(params.prefix(p).hex)"))
                    }
                }
                // TODO
            } catch { }
        }

        for cmd in commands {
            log("NFC: sending \(sensor.type) '\(cmd.description)' command: code: 0x\(cmd.code.hex), parameters: \(cmd.parameters.count == 0 ? "[]" : "0x\(cmd.parameters.hex)")")
            do {
                let output = try await connectedTag!.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
                log("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")
                if sensor.securityGeneration == 2 && output.count == 6 { // .readAttribute
                    let state = SensorState(rawValue: output[0]) ?? .unknown
                    sensor.state = state
                    log("\(sensor.type) state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")
                }
            } catch {
                log("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            }
        }
    }

}

#endif    // !os(watchOS)
