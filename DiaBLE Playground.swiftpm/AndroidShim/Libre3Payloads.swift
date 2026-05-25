import Foundation

/// Decoders for the Libre 3 payloads that arrive after AES-CCM decrypt.
/// All field layouts come from Juggluco's `bcrypt.cpp` and were verified
/// against the 2026-05-03 capture.
///
/// Multi-byte integers are little-endian. All structs are packed (no padding).
enum Libre3Payloads {
    enum DecodeError: Error, LocalizedError {
        case wrongLength(expected: Int, got: Int)
        case minimumLength(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case .wrongLength(let want, let got):
                return "Expected exactly \(want) bytes, got \(got)"
            case .minimumLength(let want, let got):
                return "Expected at least \(want) bytes, got \(got)"
            }
        }
    }

    // MARK: - One-minute glucose

    /// Named trend categories from byte 14 low 3 bits. Values match the
    /// iOS Libre3.app — see LibreCRKit `Libre3Trend`.
    enum Trend: UInt8 {
        case notDetermined = 0
        case fallingQuickly = 1
        case falling = 2
        case stable = 3
        case rising = 4
        case risingQuickly = 5
    }

    /// 29-byte plaintext following AES-CCM decrypt of the 35-byte BLE
    /// notification on the glucose-data characteristic (kind 3).
    struct OneMinute {
        var lifeCount: UInt16
        var readingMgDl: UInt16
        var rateOfChangeRaw: Int16
        var esaDuration: UInt16
        var projectedGlucose: UInt16
        var historicalLifeCount: UInt16
        var historicalReadingMgDl: UInt16
        var trend: UInt8                 // byte 14, bits 0..2
        var actionable: Bool             // byte 14, bit 3
        var rest: UInt8                  // byte 14, bits 4..7
        var uncappedCurrentMgDl: UInt16
        var uncappedHistoricMgDl: UInt16
        var temperature: UInt16
        var fastdata: Data               // 8 bytes

        var trendArrow: Trend? { Trend(rawValue: trend) }

        static let byteCount = 29
        static let validRangeMgDl: ClosedRange<Int> = 39 ... 501

        var rateOfChangePerMinute: Double {
            if rateOfChangeRaw == Int16.min {
                if trend == 0 { return .nan }
                return (Double(trend) - 3.0) * 1.3
            }
            return Double(rateOfChangeRaw) / 100.0
        }

        var preferredCurrentMgDl: UInt16 { uncappedCurrentMgDl }
        var preferredHistoricMgDl: UInt16 { uncappedHistoricMgDl }
        var isCurrentInValidRange: Bool { Self.validRangeMgDl.contains(Int(preferredCurrentMgDl)) }

        static func decode(_ data: Data) throws -> OneMinute {
            guard data.count == byteCount else {
                throw DecodeError.wrongLength(expected: byteCount, got: data.count)
            }
            let r = LittleEndianReader(data)
            let lifeCount = r.uint16(0)
            let readingMgDl = r.uint16(2)
            let rateOfChangeRaw = Int16(bitPattern: r.uint16(4))
            let esaDuration = r.uint16(6)
            let projectedGlucose = r.uint16(8)
            let historicalLifeCount = r.uint16(10)
            let historicalReadingMgDl = r.uint16(12)
            let packed = data[data.startIndex.advanced(by: 14)]
            let trend = packed & 0x07
            let actionable = (packed & 0x08) != 0
            let rest = (packed >> 4) & 0x0F
            let uncappedCurrentMgDl = r.uint16(15)
            let uncappedHistoricMgDl = r.uint16(17)
            let temperature = r.uint16(19)
            let fastdata = data.subdata(in: data.startIndex.advanced(by: 21) ..< data.startIndex.advanced(by: 29))
            return OneMinute(
                lifeCount: lifeCount,
                readingMgDl: readingMgDl,
                rateOfChangeRaw: rateOfChangeRaw,
                esaDuration: esaDuration,
                projectedGlucose: projectedGlucose,
                historicalLifeCount: historicalLifeCount,
                historicalReadingMgDl: historicalReadingMgDl,
                trend: trend,
                actionable: actionable,
                rest: rest,
                uncappedCurrentMgDl: uncappedCurrentMgDl,
                uncappedHistoricMgDl: uncappedHistoricMgDl,
                temperature: temperature,
                fastdata: fastdata
            )
        }
    }

    // MARK: - Patch status

    /// 12-byte plaintext following AES-CCM decrypt on the patch-status
    /// characteristic (kind 2).
    struct PatchStatus {
        var lifeCount: Int16
        var errorData: Int16
        /// Raw value at offset 4. Per LibreCRKit (PatchStatus.swift:58-59),
        /// this is a delta — the actual event count is `4000 + eventDataRaw`.
        var eventDataRaw: Int16
        var index: Int8
        var patchState: Int8
        var currentLifeCount: Int16
        var stackDisconnectReason: Int8
        var appDisconnectReason: Int8

        static let byteCount = 12

        var eventData: Int { 4000 + Int(eventDataRaw) }
        var totalEvents: Int { Int(index) + 1 }

        static func decode(_ data: Data) throws -> PatchStatus {
            guard data.count == byteCount else {
                throw DecodeError.wrongLength(expected: byteCount, got: data.count)
            }
            let r = LittleEndianReader(data)
            return PatchStatus(
                lifeCount: Int16(bitPattern: r.uint16(0)),
                errorData: Int16(bitPattern: r.uint16(2)),
                eventDataRaw: Int16(bitPattern: r.uint16(4)),
                index: Int8(bitPattern: data[data.startIndex.advanced(by: 6)]),
                patchState: Int8(bitPattern: data[data.startIndex.advanced(by: 7)]),
                currentLifeCount: Int16(bitPattern: r.uint16(8)),
                stackDisconnectReason: Int8(bitPattern: data[data.startIndex.advanced(by: 10)]),
                appDisconnectReason: Int8(bitPattern: data[data.startIndex.advanced(by: 11)])
            )
        }
    }

    // MARK: - Historic data

    struct History {
        var lifeCount: UInt16
        var valuesMgDl: [UInt16]

        static let minimumByteCount = 2

        static func decode(_ data: Data) throws -> History {
            guard data.count >= minimumByteCount else {
                throw DecodeError.minimumLength(expected: minimumByteCount, got: data.count)
            }
            let r = LittleEndianReader(data)
            let lifeCount = r.uint16(0)
            var values: [UInt16] = []
            var offset = 2
            while offset + 1 < data.count {
                values.append(r.uint16(offset))
                offset += 2
            }
            return History(lifeCount: lifeCount, valuesMgDl: values)
        }
    }

    // MARK: - Clinical / fast data

    struct FastData {
        var lifeCount: UInt16
        var rawData: Data        // 8 bytes
        var readingMgDl: UInt16
        var historicMgDl: UInt16

        static let byteCount = 14

        var estimatedHistoricLifeCount: UInt16 {
            // let value = (Double(lifeCount) - 19.0) / 5.0
            let value = (Double(lifeCount) - 17.0) / 5.0 // HISTORIC_POINT_LATENCY = 17
            return UInt16(value.rounded() * 5.0)
        }

        static func decode(_ data: Data) throws -> FastData {
            guard data.count == byteCount else {
                throw DecodeError.wrongLength(expected: byteCount, got: data.count)
            }
            let r = LittleEndianReader(data)
            return FastData(
                lifeCount: r.uint16(0),
                rawData: data.subdata(in: data.startIndex.advanced(by: 2) ..< data.startIndex.advanced(by: 10)),
                readingMgDl: r.uint16(10),
                historicMgDl: r.uint16(12)
            )
        }
    }

    // MARK: - Outgoing patch-control commands

    static func historyBackfillCommand(from lifeCount: Int32) -> Data {
        var data = Data([0x01, 0x00, 0x01])
        appendLittleEndian(into: &data, value: lifeCount)
        return data
    }

    static func clinicalBackfillCommand(from lifeCount: Int32) -> Data {
        var data = Data([0x01, 0x01, 0x01])
        appendLittleEndian(into: &data, value: lifeCount)
        return data
    }

    static func eventLogCommand(index: UInt8) -> Data {
        Data([0x04, index, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    static func factoryDataCommand() -> Data {
        Data([0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    static func shutdownPatchCommand() -> Data {
        Data([0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    private static func appendLittleEndian(into data: inout Data, value: Int32) {
        let bits = UInt32(bitPattern: value)
        data.append(UInt8(bits & 0xFF))
        data.append(UInt8((bits >> 8) & 0xFF))
        data.append(UInt8((bits >> 16) & 0xFF))
        data.append(UInt8((bits >> 24) & 0xFF))
    }
}

private struct LittleEndianReader {
    let data: Data
    init(_ data: Data) { self.data = data }
    func uint16(_ offset: Int) -> UInt16 {
        let i = data.startIndex.advanced(by: offset)
        let lo = UInt16(data[i])
        let hi = UInt16(data[data.index(after: i)])
        return lo | (hi << 8)
    }
}
