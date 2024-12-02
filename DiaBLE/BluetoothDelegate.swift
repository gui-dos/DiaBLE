import Foundation
import CoreBluetooth


class BluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, Logging {

    var main: MainDelegate!
    var centralManager: CBCentralManager { main.centralManager }

    /// [uuid: (name, peripheral, isConnectable, isIgnored)]
    @Published var knownDevices: [String: (name: String, peripheral: CBPeripheral, isConnectable: Bool, isIgnored: Bool)] = [:]


    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOff:
            log("Bluetooth: state: powered off")
            main.errorStatus("Bluetooth powered off")
            if app.device != nil {
                centralManager.cancelPeripheralConnection(app.device.peripheral!)
                app.device.state = .disconnected
            }
            app.deviceState = "Disconnected"
        case .poweredOn:
            if settings.stoppedBluetooth {
                log("Bluetooth: state: powered on but stopped")
                main.errorStatus("Bluetooth on but stopped")
            } else {
                log("Bluetooth: state: powered on")
                if !(settings.preferredDevicePattern.matches("abbott") || settings.preferredDevicePattern.matches("dexcom")) {
                    main.status("Scanning...")
                    log("Bluetooth: scanning...")
                    centralManager.scanForPeripherals(withServices: nil, options: nil)
                } else {
                    // TODO: use centralManager.connect() after retrieval
                    if !settings.preferredDevicePattern.matches("dexcom"),
                        let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Libre3.UUID.data.rawValue)]).first {
                        log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                        centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Libre3.UUID.data.rawValue)]], rssi: 0)
                    } else if !settings.preferredDevicePattern.matches("dexcom"),
                              let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Abbott.dataServiceUUID)]).first {
                        log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                        centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Abbott.dataServiceUUID)]], rssi: 0)
                    } else if !settings.preferredDevicePattern.matches("abbott"),
                              let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Dexcom.UUID.advertisement.rawValue)]).first {
                        log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                        centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Dexcom.UUID.advertisement.rawValue)]], rssi: 0)
                    } else {
                        log("Bluetooth: scanning for a Libre/Dexcom...")
                        main.status("Scanning for a Libre/Dexcom...")
                        centralManager.scanForPeripherals(withServices: nil, options: nil)
                    }
                }
            }
        case .resetting:    log("Bluetooth: state: resetting")
        case .unauthorized: log("Bluetooth: state: unauthorized")
        case .unknown:      log("Bluetooth: state: unknown")
        case .unsupported:  log("Bluetooth: state: unsupported")
        @unknown default:
            log("Bluetooth: state: unknown")
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData advertisement: [String: Any], rssi: NSNumber) {
        peripheral.delegate = self
        var name = peripheral.name
        let manufacturerData = advertisement[CBAdvertisementDataManufacturerDataKey] as? Data
        let dataServiceUUIDs = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let advertisedLocalName = advertisement[CBAdvertisementDataLocalNameKey] as? String
        if name == nil && advertisedLocalName != nil {
            name = advertisedLocalName
        }

        if let dataServiceUUIDs, dataServiceUUIDs.count > 0, dataServiceUUIDs[0].uuidString == Libre3.UUID.data.rawValue {
            name = "ABBOTT\(name ?? "unnamedLibre")"    // Libre 3 device name is 12 chars long (hexadecimal MAC address)
        }

        if let dataServiceUUIDs = dataServiceUUIDs, dataServiceUUIDs.count > 0, dataServiceUUIDs[0].uuidString == Dexcom.UUID.advertisement.rawValue {
            // Dexcom G7 device name starts with "DXCM" instead of "Dexcom" (both end in the last two chars of the serial number)
            if name!.hasPrefix("DXCM") {
                name = "DEXCOMG7\(name!.suffix(2))"
            }
            // Dexcom ONE+ device name starts with "DX02")
            if name!.hasPrefix("DX02") {
                name = "DEXCOMONE+\(name!.suffix(2))"
            }
            // Stelo device name is in the form DX01xx
            if name!.hasPrefix("DX01") {
                name = "DEXCOMSTELO\(name!.suffix(2))"
            }
        }

        var didFindATransmitter = false

        if let name {
            for transmitterType in TransmitterType.allCases {
                if name.matches(transmitterType.id) {
                    didFindATransmitter = true
                    if settings.preferredTransmitter != .none && transmitterType != settings.preferredTransmitter {
                        didFindATransmitter = false
                    }
                }
            }
        }

        var companyId = BLE.companies.count - 1 // "< Unknown >"
        if let manufacturerData {
            companyId = Int(manufacturerData[0]) + Int(manufacturerData[1]) << 8
            if companyId >= BLE.companies.count { companyId = BLE.companies.count - 1 }    // when 0xFFFF
        }

        if name == nil {
            name = "an unnamed peripheral"
            if BLE.companies[companyId].name != "< Unknown >" {
                name = "\(BLE.companies[companyId].name)'s unnamed peripheral"
            }
        }

        let identifier = peripheral.identifier
        let deviceIsConnectable = advertisement[CBAdvertisementDataIsConnectable] as? Int ?? 1 != 0
        var deviceIsIgnored = false
        var msg = "Bluetooth: \(name!)'s device identifier \(identifier)"
        if knownDevices[identifier.uuidString] == nil {
            msg += " not yet known"
            knownDevices[identifier.uuidString] = (name!.contains("unnamed") ? name! : peripheral.name!, peripheral, deviceIsConnectable, deviceIsIgnored)
            if settings.userLevel > .basic {
                msg += " (advertised data: \(advertisement)\(BLE.companies[companyId].name != "< Unknown >" ? ", company: \(BLE.companies[companyId].name)" : ""))"
            }
        } else {
            msg += " already known"
            deviceIsIgnored = knownDevices[identifier.uuidString]!.isIgnored
        }
        debugLog("\(msg)")

        if !deviceIsConnectable
            || deviceIsIgnored
            || (didFindATransmitter && !settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern))
            || (!didFindATransmitter && (settings.preferredTransmitter != .none || (!settings.preferredDevicePattern.isEmpty && !name!.matches(settings.preferredDevicePattern)))) {
            var scanningFor = "Scanning"
            if !settings.preferredDevicePattern.isEmpty {
                scanningFor += " for '\(settings.preferredDevicePattern)'"
            }
            main.status("\(scanningFor)...\nSkipped \(name!)")
            msg = "Bluetooth: skipped \(name!)"
            if !deviceIsConnectable {
                if !settings.preferredDevicePattern.isEmpty && name!.matches(settings.preferredDevicePattern) {
                    msg += " because not connectable"
                    main.errorStatus("(not connectable)")
                }
            }
            if deviceIsIgnored {
                if !settings.preferredDevicePattern.isEmpty && name!.matches(settings.preferredDevicePattern) {
                    msg += " because ignored"
                    main.errorStatus("(ignored)")
                }
            }
            msg += ", \(scanningFor.lowercased())..."
            log(msg)
            return
        }

        centralManager.stopScan()
        if name!.lowercased().hasPrefix("abbott") {
            app.transmitter = Abbott(peripheral: peripheral, main: main)
            app.device = app.transmitter
            if name!.count == 18 { // fictitious "ABBOTT" + Libre 3 hexadecimal MAC address
                app.device.name = "Libre 3"
                name = String(name!.suffix(12))
                if name != "unnamedLibre" {
                    app.device.macAddress = name!.bytes
                }
                (app.transmitter as! Abbott).securityGeneration = 3
                app.lastReadingDate = Date() // TODO
            } else {
                app.device.serial = String(name!.suffix(name!.count - 6))
                switch app.device.serial.prefix(1) {
                case "7":
                    app.device.name = "Libre Sense"
                    (app.transmitter as! Abbott).securityGeneration = 2
                case "3":
                    app.device.name = "Libre 2"
                default: app.device.name = "Libre"
                    // TODO: Libre 2 US / CA
                }
            }
            settings.activeSensorSerial = app.device.serial

        } else if name!.lowercased().hasPrefix("dexcom") {
            app.transmitter = Dexcom(peripheral: peripheral, main: main)
            app.device = app.transmitter
            if name!.hasPrefix("Dexcom") {
                app.device.name = "Dexcom"         // TODO: separate Dexcom G6 and ONE
            } else if name!.hasPrefix("DEXCOMG7") {  // restore to the original G7 device name
                app.device.name = "Dexcom G7"
                name = "DXCM" + name!.suffix(2)
            } else if name!.hasPrefix("DEXCOMONE+") {  // restore to the original ONE+ device name
                app.device.name = "Dexcom ONE+"
                name = "DX02" + name!.suffix(2)
            } else if name!.hasPrefix("DEXCOMSTELO") {  // restore to the original Stelo device name
                app.device.name = "Stelo"
                name = "DX01" + name!.suffix(2)
            }
            let serialSuffix = name!.suffix(2)
            if !(settings.activeTransmitterSerial.count == 6 && settings.activeTransmitterSerial.suffix(2) == serialSuffix) {
                app.device.serial = "XXXX" + name!.suffix(2)
                settings.activeTransmitterSerial = app.device.serial
            } else {
                app.device.serial = settings.activeTransmitterSerial
            }

            // } else if name.matches("custom") {
            //    custom = Custom(peripheral: peripheral, main: main)
            //    app.device = custom
            //    app.device.name = peripheral.name!
            //    app.transmitter = custom.transmitter
            //    app.transmitter.name = "bridge"

        } else {
            app.device = Device(peripheral: peripheral, main: main)
            app.device.name = name!.replacingOccurrences(of: "an unnamed", with: "Unnamed")
        }

        app.device.rssi = Int(truncating: rssi)
        app.device.company = BLE.companies[companyId].name
        msg = "Bluetooth: found \(name!): RSSI: \(rssi), advertised data: \(advertisement)"
        if app.device.company == "< Unknown >" {
            if companyId != BLE.companies.count - 1 {
                msg += ", company id: \(companyId) (0x\(companyId.hex), unknown)"
            }
        } else {
            msg += ", company: \(app.device.company) (id: 0x\(companyId.hex))"
        }
        log(msg)
        if let manufacturerData {
            app.device.parseManufacturerData(manufacturerData)
        }
        if let dataServiceUUIDs {
            // TODO: assign to device instance vars
            log("Bluetooth: \(name!)'s advertised data service UUIDs: \(dataServiceUUIDs)")
        }
        main.status("\(app.device.name)")
        app.device.peripheral?.delegate = self
        log("Bluetooth: connecting to \(name!)...")
        centralManager.connect(app.device.peripheral!, options: nil)
        app.device.state = app.device.peripheral!.state
        app.deviceState = app.device.state.description.capitalized + "..."
    }


    public func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var msg = "Bluetooth: \(name) has connected"
        app.device.state = peripheral.state
        app.deviceState = app.device.state.description.capitalized
        app.device.lastConnectionDate = Date()
        app.lastConnectionDate = app.device.lastConnectionDate
        msg += ("; discovering services")
        peripheral.discoverServices(nil)
        log(msg)
    }


    public func centralManager(_ manager: CBCentralManager, willRestoreState dict: [String: Any]) {
        log("Bluetooth: will restore state to \(dict.debugDescription)")
    }


    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let name = peripheral.name ?? "unnamed peripheral"
        if app.device.name == "Unnamed peripheral" && name != "unnamed peripheral" {
            app.device.name = name
            main.status("\(app.device.name)")
            knownDevices[peripheral.identifier.uuidString]!.name = name
        }
        app.device.state = peripheral.state
        if let services = peripheral.services {
            for service in services {
                let serviceUUID = service.uuid.uuidString
                var description = "unknown service"
                if serviceUUID == type(of: app.device).dataServiceUUID {
                    description = "data service"
                }
                if [Libre3.UUID.data.rawValue, Libre3.UUID.security.rawValue].contains(serviceUUID) {
                    description = Libre3.UUID(rawValue: serviceUUID)!.description
                }
                if let uuid = BLE.UUID(rawValue: serviceUUID) {
                    description = uuid.description
                }
                var msg = "Bluetooth: discovered \(name)'s service \(serviceUUID) (\(description))"
                if !(serviceUUID == BLE.UUID.device.rawValue && app.device.characteristics[BLE.UUID.manufacturer.rawValue] != nil) {
                    msg += "; discovering characteristics"
                    peripheral.discoverCharacteristics(nil, for: service)
                }
                log(msg)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            log("Bluetooth: unable to retrieve service characteristics")
            return
        }

        let serviceUUID = service.uuid.uuidString
        var serviceDescription = serviceUUID
        if serviceUUID == type(of: app.device).dataServiceUUID || serviceUUID == Libre3.UUID.data.rawValue {
            serviceDescription = "data"
        }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString

            var msg = "Bluetooth: discovered \(app.device.name) \(serviceDescription) service's characteristic \(uuid)"
            msg += (", properties: \(characteristic.properties)")

            if Libre3.knownUUIDs.contains(uuid) {
                msg += " (\(Libre3.UUID(rawValue: uuid)!.description))"
            }

            if Dexcom.knownUUIDs.contains(uuid) {
                msg += " (\(Dexcom.UUID(rawValue: uuid)!.description))"
                let transmitterIsAuthenticated = (app.transmitter as? Dexcom)?.authenticated ?? false

                if uuid == Dexcom.UUID.control.rawValue {
                    app.device.readCharacteristic = characteristic
                    app.device.writeCharacteristic = characteristic
                    if settings.userLevel >= .test && transmitterIsAuthenticated {
                        peripheral.setNotifyValue(true, for: characteristic)
                        msg += "; enabling notifications"
                    } else {
                        msg += "; avoid enabling notifications because of 'Encryption is insufficient' error"
                    }

                } else if uuid == Dexcom.UUID.backfill.rawValue
                            || uuid == Dexcom.UUID.communication.rawValue {
                    if settings.userLevel >= .test && transmitterIsAuthenticated {
                        peripheral.setNotifyValue(true, for: characteristic)
                        msg += "; enabling notifications"
                    } else {
                        msg += "; avoid enabling notifications because of 'Encryption is insufficient' error"
                    }

                } else {
                    peripheral.setNotifyValue(true, for: characteristic)
                    msg += "; enabling notifications"
                }

            } else if uuid == Libre3.UUID.patchStatus.rawValue {
                msg += "; avoid enabling notifications because of 'Encryption is insufficient' error"

            } else if uuid == Abbott.dataReadCharacteristicUUID {
                app.device.readCharacteristic = characteristic
                msg += " (data read)"

                // enable notifications only in didWriteValueFor() unless eavesdropping the Libre 2 in TEST mode
                if uuid != Abbott.dataReadCharacteristicUUID || settings.userLevel >= .test {
                    app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                    msg += "; enabling notifications"
                }

            } else if uuid == Abbott.dataWriteCharacteristicUUID {
                msg += " (data write)"
                app.device.writeCharacteristic = characteristic


            // } else if let uuid = Custom.UUID(rawValue: uuid) {
            //    msg += " (\(uuid))"
            //    if uuid.description.contains("unknown") {
            //        if characteristic.properties.contains(.notify) {
            //            app.device.peripheral?.setNotifyValue(true, for: characteristic)
            //        }
            //        if characteristic.properties.contains(.read) {
            //            app.device.peripheral?.readValue(for: characteristic)
            //            msg += "; reading it"
            //        }
            //    }


            } else if let uuid = BLE.UUID(rawValue: uuid) {
                if uuid == .batteryLevel {
                    app.device.peripheral?.setNotifyValue(true, for: characteristic)
                }

                if app.device.characteristics[uuid.rawValue] != nil {
                    msg += " (\(uuid)); already read it"
                } else {
                    app.device.peripheral?.readValue(for: characteristic)
                    msg += " (\(uuid)); reading it"
                }

                // } else if let uuid = OtherDevice.UUID(rawValue: uuid) {
                //    msg += " (\(uuid))"

            } else {
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    msg += "; enabling notifications"
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                    msg += "; reading it"
                }
            }

            log(msg)

            app.device.characteristics[uuid] = characteristic

        }

        if app.device.type == .transmitter(.abbott) && (serviceUUID == Abbott.dataServiceUUID || serviceUUID == Libre3.UUID.data.rawValue || serviceUUID == Libre3.UUID.security.rawValue) {
            var sensor: Sensor! = app.sensor
            if app.sensor == nil || (app.sensor.transmitter?.type != app.device.type && sensor.uid != (app.device as! Abbott).sensorUid) {
                if serviceUUID == Libre3.UUID.data.rawValue {
                    sensor = Libre3(transmitter: app.transmitter)
                } else {
                    sensor = Libre2(transmitter: app.transmitter)
                }
                app.sensor = sensor
                sensor.state = .active
                sensor.uid = (app.device as! Abbott).sensorUid
                // TODO
                settings.currentSensorUid = sensor.uid

                if settings.activeSensorSerial == app.device.serial {
                    if !app.device.serial.isEmpty && !settings.currentPatchInfo.isEmpty {
                        (sensor as! Libre).patchInfo = settings.currentPatchInfo

                    } else {
                        sensor.serial = app.device.serial
                        let family = Int(app.device.serial.prefix(1)) ?? 0
                        switch family {
                        case 3:  sensor.type = .libre2
                        case 0:  sensor.type = .libre3
                        default: sensor.type = .libre2
                            // TODO: .libre2Gen2
                        }
                        sensor.family = SensorFamily(rawValue: family) ?? .libre2
                    }
                }
            }

            app.transmitter.sensor = sensor

            if !app.device.serial.isEmpty && app.device.serial == settings.activeSensorSerial {
                (sensor as? Libre2)?.initialPatchInfo = settings.activeSensorInitialPatchInfo
                (sensor as? Libre2)?.streamingUnlockCode = UInt32(settings.activeSensorStreamingUnlockCode)
                (sensor as? Libre2)?.streamingUnlockCount = UInt16(settings.activeSensorStreamingUnlockCount)
                sensor.calibrationInfo = settings.activeSensorCalibrationInfo
                sensor.maxLife = settings.activeSensorMaxLife
                var msg = "Bluetooth: the active sensor \(app.device.serial) has reconnected"
                if let libre2 = sensor as? Libre2 {
                    msg += "; restoring settings: initial patch info: \(libre2.initialPatchInfo.hex), current patch info: \(libre2.patchInfo.hex), unlock count: \(libre2.streamingUnlockCount)"
                }
                log(msg)
                app.device.macAddress = settings.activeSensorAddress
            }

            if serviceUUID == Libre3.UUID.security.rawValue {
                if sensor.transmitter == nil { sensor.transmitter = app.transmitter }
                if settings.userLevel < .test { // not eavesdropping Trident
                    ((app.device as? Abbott)?.sensor as? Libre3)?.send(securityCommand: .readChallenge)
                    // ((app.device as? Abbott)?.sensor as? Libre3)?.pair()  // TEST
                }

            } else if (app.transmitter as! Abbott).securityGeneration == 2 && (app.transmitter as! Abbott).authenticationState == .notAuthenticated {
                app.device.peripheral?.setNotifyValue(true, for: app.device.writeCharacteristic!)
                (app.transmitter as! Abbott).authenticationState = .enableNotification
                debugLog("Bluetooth: enabled \(app.device.name) security notification")
                // TODO: move to didUpdateNotificationStateFor()
                (app.transmitter as! Abbott).authenticationState = .challengeResponse
                app.device.write(Data([0x20]), .withResponse)
                debugLog("Bluetooth: sent \(app.device.name) read security challenge")

            } else if sensor.uid.count > 0 && settings.activeSensorInitialPatchInfo.count > 0 {
                if let libre2 = sensor as? Libre2, settings.userLevel < .test {  // not eavesdropping Libre 2
                    libre2.streamingUnlockCount += 1
                    settings.activeSensorStreamingUnlockCount += 1
                    let unlockPayload = Libre2.streamingUnlockPayload(id: sensor.uid, info: settings.activeSensorInitialPatchInfo, enableTime: libre2.streamingUnlockCode, unlockCount: libre2.streamingUnlockCount)
                    log("Bluetooth: writing streaming unlock payload: \(Data(unlockPayload).hex) (patch info: \(settings.activeSensorInitialPatchInfo.hex), unlock code: \(libre2.streamingUnlockCode), unlock count: \(libre2.streamingUnlockCount), sensor id: \(libre2.uid.hex), current patch info: \(libre2.patchInfo.hex))")
                    app.device.write(unlockPayload, .withResponse)
                }
            }
        }

        if app.device.type == .transmitter(.dexcom) && serviceUUID == Dexcom.dataServiceUUID {
            var sensor: Sensor! = app.sensor
            if sensor == nil || sensor.type != .dexcomG6 || sensor.type != .dexcomONE || sensor.type != .dexcomG7 || sensor.type != .dexcomONEPlus {
                if app.device.name.suffix(2) == "G7" {
                    sensor = DexcomG7(transmitter: app.transmitter)
                    sensor.type = .dexcomG7
                } else if app.device.name.suffix(4) == "ONE+" {
                    sensor = DexcomONEPlus(transmitter: app.transmitter)
                    sensor.type = .dexcomONEPlus
                } else if app.device.name.prefix(5) == "Stelo" {
                    sensor = Stelo(transmitter: app.transmitter)
                    sensor.type = .stelo
                } else {
                    // TODO: default type should be DexcomG6
                    sensor = DexcomONE(transmitter: app.transmitter)
                    sensor.type = .dexcomONE
                }
                app.sensor = sensor
            }
            app.transmitter.sensor = sensor
            if settings.userLevel < .test { // not eavesdropping

                // G7 uses appKeyChallenge/authRequest2Tx (0x02), see: https://github.com/NightscoutFoundation/xDrip/blob/master/libkeks/src/main/java/jamorham/keks/message/AuthRequestTxMessage2.java
                // TODO: send 01 00 first anyway
                var message = (sensor.type == .dexcomG7 || sensor.type == .stelo || sensor.type == .dexcomONEPlus || sensor.type == .dexcomONE) ? DexcomG7.Opcode.appKeyChallenge.data : Dexcom.Opcode.authRequestTx.data
                let singleUseToken = UUID().uuidString.data(using: .utf8)!.prefix(8)
                message += singleUseToken
                message.append(0x02)
                log("Bluetooth: sending \(app.device.name) authentication request: \(message.hex)")
                app.device.write(message, for: Dexcom.UUID.authentication.rawValue, .withResponse)

                // TEST: first JPake phase: send exchangePakePayload 0a + 00 phase
                if sensor.type == .dexcomG7 || sensor.type == .stelo || sensor.type == .dexcomONEPlus || sensor.type == .dexcomONE {
                    let message = Dexcom.Opcode.exchangePakePayload.data + Dexcom.PakePhase.zero.rawValue.data
                    log("TEST: sending \(app.device.name) 'exchangePakePayload phase zero' command \(message.hex)")
                    app.device.write(message, for: Dexcom.UUID.authentication.rawValue, .withResponse)
                }

            }
        }
    }


    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        app.device?.state = peripheral.state
        app.deviceState = peripheral.state.description.capitalized
        if error != nil {
            log("Bluetooth: \(name) has disconnected.")
            let errorCode = CBError.Code(rawValue: (error! as NSError).code)! // 6 = timed out when out of range
            log("Bluetooth: error type \(errorCode.rawValue): \(error!.localizedDescription)")
            if app.transmitter != nil && (settings.preferredTransmitter == .none || settings.preferredTransmitter.id == app.transmitter.type.id) {
                app.deviceState = "Reconnecting..."
                log("Bluetooth: reconnecting to \(name)...")
                if errorCode == .connectionTimeout { main.errorStatus("Connection timed out. Waiting...") }
                app.device.buffer = Data()
                // TODO: Dexcom reconnection
                if app.transmitter.type == .transmitter(.dexcom) {
                    debugLog("DEBUG: Dexcom: sleeping 2 seconds before rescanning to reconnect")
                    self.main.status("Scanning for Dexcom...") //  allow stopping from Console
                    DispatchQueue.global(qos: .utility).async {
                        Thread.sleep(forTimeInterval: 2)
                        // self.centralManager.connect(peripheral, options: nil)
                        // https://github.com/LoopKit/G7SensorKit/blob/14205c1/G7SensorKit/G7CGMManager/G7BluetoothManager.swift#L224-L229
                        self.centralManager.scanForPeripherals(withServices: [CBUUID(string: Dexcom.UUID.advertisement.rawValue)], options: nil)
                    }
                } else {
                    centralManager.connect(peripheral, options: nil)
                }
            } else {
                let lastConnectionDate = Date()
                app.device?.lastConnectionDate = lastConnectionDate
                app.lastConnectionDate = lastConnectionDate
                // app.device = nil
                // app.transmitter = nil
            }
        } else {
            log("Bluetooth: stopped connecting with \(name).")
            app.device.lastConnectionDate = Date()
            app.lastConnectionDate = app.device.lastConnectionDate
            // app.device = nil
            // app.transmitter = nil
        }
    }

    public func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var msg = "Bluetooth: failed to connect to \(name)"
        var errorCode: CBError.Code?

        if let error {
            errorCode = CBError.Code(rawValue: (error as NSError).code)
            msg += ", error type \(errorCode!.rawValue): \(error.localizedDescription)"
        }

        if let errorCode, errorCode == .peerRemovedPairingInformation {  // i.e. BluCon
            main.errorStatus("Failed to connect: \(error!.localizedDescription)")
        } else {
            msg += "; retrying..."
            main.errorStatus("Failed to connect, retrying...")
            centralManager.connect(app.device.peripheral!, options: nil)
        }

        log(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Abbott.dataWriteCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data write"
        }
        if let characteristicDescription = Libre3.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }
        if let characteristicDescription = Dexcom.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }
        if error != nil {
            log("Bluetooth: error while writing \(name)'s \(characteristicString) characteristic value: \(error!.localizedDescription)")
        } else {
            log("Bluetooth: \(name) did write value for \(characteristicString) characteristic")
            if characteristic.uuid.uuidString == Abbott.dataWriteCharacteristicUUID {
                app.device.peripheral?.setNotifyValue(true, for: app.device.readCharacteristic!)
                log("Bluetooth: enabling data read notifications for \(name)")
            }
        }
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString
        if [Abbott.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        if let characteristicDescription = Libre3.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }
        if let characteristicDescription = Dexcom.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }
        var msg = "Bluetooth: \(name) did update notification state for \(characteristicString) characteristic"
        msg += ": \(characteristic.isNotifying ? "" : "not ")notifying"
        if let descriptors = characteristic.descriptors { msg += ", descriptors: \(descriptors)" }
        if let error {
            let errorCode = CBError.Code(rawValue: (error as NSError).code)!
            if errorCode == .encryptionTimedOut {
                log("Bluetooth: DEBUG: TODO: manage pairing timeout")
                // TODO: manage pairing
            }
            msg += ", error: \(error.localizedDescription)"
        }
        log(msg)
    }


    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI rssi: NSNumber, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        if let error {
            debugLog("Bluetooth: error reading \(name)'s RSSI: \(error.localizedDescription)")
        } else {
            debugLog("Bluetooth: did read \(name)'s RSSI: \(rssi) dB")
            app.device.rssi = Int(truncating: rssi)
        }
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = peripheral.name ?? "an unnamed peripheral"
        var characteristicString = characteristic.uuid.uuidString

        if [Abbott.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        if let characteristicDescription = Libre3.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }
        if let characteristicDescription = Dexcom.UUID(rawValue: characteristicString)?.description {
            characteristicString = characteristicDescription
        }

        guard let data = characteristic.value else {
            log("Bluetooth: \(name)'s error updating value for \(characteristicString) characteristic: \(error!.localizedDescription)")
            return
        }

        var msg = "Bluetooth: \(name) did update value for \(characteristicString) characteristic (\(data.count) bytes received):"
        if data.count > 0 {
            msg += " hex: \(data.hex),"
        }

        if let uuid = BLE.UUID(rawValue: characteristic.uuid.uuidString) {

            log("\(msg) \(uuid): \(uuid != .batteryLevel ? "\"\(data.string)\"" : String(Int(data[0])))")

            switch uuid {

            case .batteryLevel:
                app.device.battery = Int(data[0])
            case .model:
                app.device.model = data.string
                if app.device.peripheral?.name == nil {
                    app.device.name = app.device.model
                    main.status(app.device.name)
                }
            case .serial:
                app.device.serial = data.string
            case .firmware:
                app.device.firmware = data.string
            case .hardware:
                app.device.hardware += data.string
            case .software:
                app.device.software = data.string
            case .manufacturer:
                app.device.manufacturer = data.string

            default:
                break
            }

        } else {

            log("\(msg) string: \"\(data.string)\"")


            if app.device == nil { return }     // the connection timed out in the meantime

            app.device.lastConnectionDate = Date()
            if Int(app.lastConnectionDate.distance(to: app.device.lastConnectionDate)) >= settings.readingInterval * 60 - 5 {
                app.device.peripheral!.readRSSI()
            }
            app.lastConnectionDate = app.device.lastConnectionDate

            app.device.read(data, for: characteristic.uuid.uuidString)

            if app.device.type == .transmitter(.abbott) {
                if app.transmitter.buffer.count == 46 {
                    main.didParseSensor(app.transmitter.sensor!)
                    app.transmitter.buffer = Data()
                }

            } else if app.device.type == .transmitter(.dexcom) {
                // TODO:
                // main.didParseSensor(app.transmitter.sensor!)
                return

            } else if app.transmitter?.sensor != nil {
                main.didParseSensor(app.transmitter.sensor!)
                app.transmitter.buffer = Data()
            }
        }
    }
}
