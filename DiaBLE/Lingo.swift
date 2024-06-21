// Lingo Metabolic Coaching: https://decrypt.day/app/id1670445335

// Lingo.app/Frameworks/BSMCoreKit.framework


// enum DCMGK.GKAnalyteType {
//     case INACTIVE
//     case GLUCOSE
//     case KETONE
//     case LACTATE
// }


// enum DCMGK.DCSGKPatchState {
//     case UNDEFINED
//     case MANUFACTURING
//     case STORAGE
//     case INSERTION_DETECTION
//     case INSERTION_FAILED
//     case PAIRED
//     case EXPIRED
//     case TERMINATED_NORMAL
//     case ERROR
//     case ERROR_TERMINATED
// }


// enum DCMGK.GKSensorCondition {
//     case OK
//     case Invalid
//     case ESA
// }


// class DCMGK.GKSensor {
//     var sensor: DCSCore.IAnalyteSensor
//     var deviceType: Swift.Int
//     var cryptoLib: DCMGK.IGKCryptoLib?
//     var securityContext: DCSCore.ISecurityContext?
//     var patchEphemeral: Foundation.Data?
//     var r1: Foundation.Data?
//     var r2: Foundation.Data?
//     var nonce1: Foundation.Data?
//     var kEnc: Foundation.Data?
//     var ivEnc: Foundation.Data?
//     var exportedkAuth: Foundation.Data?
//     var securityLibInitialized: Swift.Bool
//     var isPreAuthorized: Swift.Bool
//     var initParam: DCMGK.GKSensorInitParam
//     var securityVersion: Swift.Int32
// }


// class DCMGK.GKSPL {
//     var lastError: Swift.Int
//     let MIN_LIFECOUNT_FOR_HISTORICAL_DATA: Swift.Int
//     let MIN_HISTORICAL_DATA_LIFECOUNT_OFFSET: Swift.Int
// }


// class DCMGK.GKBLESensor {
//     let splInterface: DCMGK.GKSPL
//     let stateMachine: DCMGK.GKStateMachine
//     var deviceUID: Swift.String
//     let msdevice: DCSCore.DCSDevice
//     var initParam: DCMGK.GKSensorInitParam
//     var callback: DCSCore.BLECentralCallback?
//     var activeBlePeripheral: DCSCore.BlePeripheral?
//     var oneMinuteRawData: Foundation.Data
//     var isScanning: Swift.Bool
//     var undiscoveredRequiredServiceUUIDs: Swift.Set<Swift.String>
//     var undiscoveredRequiredCharacteristicUUIDs: Swift.Set<Swift.String>
//     var incompleteServices: Swift.Set<Swift.String>
//     var hybridMode: Swift.Bool
//     var mHistoricLifeCount: Swift.Int
//     var historicalRecordCount: Swift.Int
//     var retrievedHistoricalData: Swift.Bool
//     var securityContext: DCSCore.ISecurityContext?
//     var wasAuthorized: Swift.Bool
//     var rdtData: Foundation.Data
//     var factoryData: Foundation.Data
//     var rssiCompletionEvent: DCMGK.DCSGKSEvent?
//     var WRITE_AT_OFFSET_ENABLED: Swift.Bool
//     var wrtData: Foundation.Data?
//     var wrtOffset: Swift.Int?
//     var rdtLength: Swift.Int?
//     var rdtBytes: Swift.Int?
//     var rdtSequence: Swift.Int?
//     var MAX_WRITE_OFFSET_DATA_LENGTH: Swift.Int
//     var isServicesDiscovered: Swift.Bool
//     var backFillInProgress: Swift.Bool
//     var backFillsPending: Swift.Int
//     var sessionEnded: Swift.Bool
//     var securedConnection: Swift.Bool
//     var currentControlCommand: DCMGK.GKCommand?
//     var currentLifeCount: Swift.Int
//     var currentGlucoseDateTime: Foundation.Date
//     var controlCommandQue: [DCMGK.GKCommand]
//     var loggingEventCancellable: Combine.AnyCancellable?
//     var isTimeChangeNotificationTriggered: Swift.Bool
//     var timerReading: DCSCore.LibreTimer?
//     var timerAuthentication: DCSCore.LibreTimer?
//     var timerPatchStatus: DCSCore.LibreTimer?
//     var timerConnectionMode: DCSCore.LibreTimer?
//     var wasConnected: Swift.Bool
//     var sensorEndTimeUTC: Foundation.Date
//     var securityState: Swift.Int
//     let STATE_NONE: Swift.Int
//     let STATE_AUTHENTICATING: Swift.Int
//     let STATE_AUTHORIZING: Swift.Int
//     var inShutDown: Swift.Bool
//     var shutDownEvent: DCMGK.DCSGKSEvent?
//     var scanType: Swift.Character
//     var analytes: [DCMGK.GKAnalyteType]
//     var pendingTermination: Swift.Bool
//     var terminateReason: DCMGK.DCSGKPatchState
//     let HISTORIC_POINT_LATENCY: Swift.Int
//     var oneMinuteTimeChangeNotification: Swift.Bool
// }


// class DCSCore.ADCProductTypeConfig {
//     var productType: Swift.Int
//     var generations: [Swift.Int]
// }


// class DCMGK.GKSDCMConfig {
//     var supportedTypes: [DCSCore.ADCProductTypeConfig]
// }


// class DCMGK.GKDeviceControlModule {
//     let deviceManager: DCSCore.DCSDeviceManager?
//     var stateMachineDefinition: DCSCore.StateMachineDefinition?
//     let tag: Swift.String
//     let STATE_MACHINE_DEFINITION_TYPE: Swift.String
//     var activities: [Swift.AnyObject.Type]?
//     var events: [Swift.AnyObject.Type]?
//     var lastError: Swift.Int
//     let RESPONSE_FAILED: Swift.Int = 1
//     let RESPONSE_DUMMY: Swift.Int  = 2
//     let RESPONSE_OK: Swift.Int     = 3
//     let MAX_NFC_RETRIES: Swift.Int = 5
//     let EM_BOOT_TIME_MS: Swift.UInt32 = 80
//     let ACTIVATION_DELAY_MS: Swift.UInt32 = 600
//     let NFC_RETRY_DELAY_MS: Swift.UInt32 = 150
//     let RESPONSE_ERROR: Swift.Int
//     let LIB_NV_MEMORY_SIZE: Swift.Int = 1024
//     let ACTIVATION_ERROR_LOW_BATTERY: Swift.Int = 0xa0
//     let NFC_GET_PATCH_CUSTOM_COMMAND: Swift.Int = 0xa1
//     let ACTIVATION_ERROR_MANUFACTURING_STATE: Swift.Int       = 0xa2
//     let ACTIVATION_ERROR_INSERTION_DETECTION_STATE: Swift.Int = 0xa4
//     let ACTIVATION_ERROR_PAIRED_STATE: Swift.Int = 0xa4       = 0xa5
//     let ACTIVATION_ERROR_EXPIRED_STATE: Swift.Int             = 0xa6
//     let ACTIVATION_ERROR_TERMINATION_NORMAL: Swift.Int        = 0xa7
//     let ACTIVATION_ERROR_TERMINATION_ERROR: Swift.Int         = 0xa8
//     let ACTIVATION_ERROR_NFC_COMMUNICATION_FAILURE: Swift.Int = 1
//     let ACTIVATION_ERROR_CRL_ERROR: Swift.Int                 = 2
//     let MANUFACTURER_CODE: Swift.Int = 0x7a
//     var CMD_SWITCH_RECEIVER: Swift.Int    = 0xA8
//     var dcmConfig: DCMGK.GKSDCMConfig?
//     var NFC_ACTIVATION_COMMAND: Swift.Int = 0xA0
//     var nfcActivationByteArray: Foundation.Data
//     var sensorUID: Swift.String
//     let hexArray: [Swift.Character]
//     let getPatchInfoGroup: __C.OS_dispatch_group
//     let splInterface: DCMGK.GKSPL
// }


// class DCMGK.GKSensorInitParam {
//     let activationTime: Foundation.Date
//     var firstConnect: Swift.Bool
//     let serialNumber: Swift.String
//     var hybridModeEnabled: Swift.Bool
//     var dataFile: Swift.String?
//     var blePIN: Foundation.Data
//     let deviceAddress: Swift.String
//     let warmupDuration: Swift.Int
//     let wearDuration: Swift.Int
//     var exportedKAuth: Foundation.Data?
//     let securityVersion: Swift.Int32
//     var lastEventReceived: Swift.Int
//     var lastLifeCountsReceived: [DCMGK.DCSGKSLastLifeCounts]
//     var resolved: Swift.Bool
// }


// class DCMGK.GKBCSecurityContext {
//     var packetDescriptorArray: [[Swift.UInt8]]
//     let NONCE_COUNTER_OFFSET: Swift.Int
//     let NONCE_PACKET_DESCRIPTOR_OFFSET: Swift.Int
//     let NONCE_IV_OFFSET: Swift.Int
//     let IV_ENC_SIZE: Swift.Int
//     var key: [Swift.UInt8]?
//     var iv_enc: [Swift.UInt8]?
//     var nonce: [Swift.UInt8]?
//     var outCryptoSequence: Swift.UInt16
// }


// class DCMGK.GKSKBCryptoLib {
//     var g_engine: Swift.OpaquePointer?
//     let CRYPTO_EXTENSION_INIT_LIB: Swift.Int
//     let CRYPTO_RETURN_SUCCESS: Swift.Int
//     let CRYPTO_EXTENSION_INIT_ECDH: Swift.Int
//     let CRYPTO_EXTENSION_SET_PATCH_ATTRIB: Swift.Int
//     let CRYPTO_EXTENSION_SET_CERTIFICATE: Swift.Int
//     let CRYPTO_EXTENSION_GENERATE_EPHEMERAL: Swift.Int
//     let CRYPTO_EXTENSION_GENERATE_KAUTH: Swift.Int
//     let CRYPTO_EXTENSION_ENCRYPT: Swift.Int
//     let CRYPTO_EXTENSION_DECRYPT: Swift.Int
//     let CRYPTO_EXTENSION_EXPORT_KAUTH: Swift.Int
//     let PUBLIC_KEY_TYPE_UNCOMPRESSED: Swift.UInt8
//     let CRYPTO_PUBLIC_KEY_SIZE: Swift.Int
//     let CRYPTO_EXTENSION_WRAP_DIAGNOSTIC_DATA: Swift.Int
//     let CRYPTO_RETURN_INVALID_PARAM: Swift.Int
//     var patchSigningKey: __C.NSData?
//     var securityVersion: Swift.Int
//     var keyIndex: Swift.Int
//     var max_key_index: Swift.Int
//     var app_private_key: [Swift.UInt8]
//     var app_certificate: [Swift.UInt8]
// }


// enum DCMGK.GKResultRange {
//     case IN_RANGE
//     case BELOW_RANGE
//     case ABOVE_RANGE
// }


// enum DCMGK.ABT_GLUCOSE_RESULT_RANGE_STATUS {
//     case IN_RANGE
//     case BELOW_RANGE
//     case ABOVE_RANGE
//     case RESERVED
// }


// enum DCMGK.GKTemperatureRange {
//     case TEMPERATURE_IN_RANGE
//     case TEMPERATURE_BELOW_RANGE
//     case TEMPERATURE_ABOVE_RANGE
//     case TEMPERATURE_OUT_OF_RANGE
// }


// enum DCMGK.ABT_TEMPERATURE_RANGE {
//     case IN_RANGE
//     case BELOW_RANGE
//     case ABOVE_RANGE
//     case OUT_OF_RANGE
// }


// enum DCMGK.ABT_TREND_ARROW_BIN {
//     case NOT_DETERMINED
//     case FALLING_QUICKLY
//     case FALLING
//     case STABLE
//     case RISING
//     case RISING_QUICKLY
// }


// enum DCMGK.ABT_GLYCEMIC_ALARM {
//     case NOT_DETERMINED
//     case LOW_GLUCOSE
//     case PROJECTED_LOW_GLUCOSE
//     case GLUCOSE_OK
//     case PROJECTED_HIGH_GLUCOSE
//     case HIGH_GLUCOSE
// }


// struct DCMGK.DCSGKSPatchInfo {
//     var securityVersion: Swift.Int
//     var generation: Swift.Int
//     var localization: Swift.Int
//     var wearDuration: Swift.Int
//     var warmupDuration: Swift.Int
//     var DMX: Foundation.Data
//     var fwVersion: Foundation.Data
//     var productType: Swift.Int
//     var state: DCMGK.DCSGKPatchState?
//     var mode: Swift.Int
// }


// struct DCMGK.DCSGKSPatchStatus {
//     var serialNumber: Swift.String
//     var patchEvent: DCMGK.DCSGKSPatchEvent?
//     var index: Swift.Int
//     var patchState: DCMGK.DCSGKPatchState
//     var lifeCount: Swift.Int
//     var appDisconnectReason: Swift.Int
//     var stackDisconnectReason: Swift.Int
//     var firstAnalyteType: DCMGK.GKAnalyteType
//     var secondAnalyteType: DCMGK.GKAnalyteType
// }


// struct DCMGK.DCSGKSFastData {
//     var rawData: Foundation.Data
//     var unCappedReading: Swift.Double
//     var dqFlag: Swift.Int
//     var historicLifeCount: Swift.Int
//     var unCappedHistoric: Swift.Double
//     var historicDQFlag: Swift.Int
//     var analyte: DCMGK.GKAnalyteType
//     var lifeCount: Swift.Int
// }


// struct DCMGK.GKSPLActivationResponse {
//     var isActivated: Swift.Bool
//     var status: Swift.Int
//     var BLEAddress: Foundation.Data
//     var BLEPin: Foundation.Data
//     var activationTimeEpoch: Swift.Int
// }


// class BSMCoreKit.BSMAnalyteMeasurement {
//     let analyte: Swift.Int
//     let cappedReading: Swift.Double
//     let dqFlag: Swift.Int
//     let resultRange: Swift.Int
//     let rateOfChange: Swift.Double
//     let esaDuration: Swift.Int
//     let projectedReading: Swift.Double
//     let cappedHistoric: Swift.Double
//     let historicDQFlag: Swift.Int
//     let historicResultRange: Swift.Int
//     let actionable: Swift.Bool
//     let trend: Swift.Int
//     let unCappedReading: Swift.Double
//     let unCappedHistoric: Swift.Double
//     let sensorCondition: Swift.Int
// }


// class BSMCoreKit.BSMHistoricReading {
//     let lifeCount: Swift.Int
//     let cappedHistoricReading: Swift.Double
//     let resultRange: Swift.Int
//     let dqFlag: Swift.Int
// }


// class DCSCore.LibreTimer {
//     var client: DCSCore.ITimedClient
//     var paramObject: Swift.AnyObject
//     var mIsAlive: Swift.Int32
//     var onUiThread: Swift.Bool
//     var end: Swift.Int
//     var timeout: Swift.Int
//     var mEnd: Swift.Int
// }


// class DCSCore.DCSDevice {
//     var deviceId: Swift.Int64
//     var typeId: Swift.Int
//     var address: Swift.String
//     var active: Swift.Bool
// }


// enum DCSCore.DCSActivationError {
//     case notSupported
//     case alreadyActivated
//     case success
//     case incompatible
//     case terminated
//     case scanError
//     case sensorError
//     case notYours
//     case insertionFailed
//     case sensorExpired
//     case nfcTagConnectionLost
// }


// class DCSCore.DCSActivationResponse {
//     var status: Swift.Bool
//     let device: DCSCore.DCSDevice?
//     var errorCode: DCSCore.DCSActivationError
// }


// class DCMGK.GKStateMachine {
//     var sensor: DCSCore.IAnalyteSensor?
//     var msDevice: DCSCore.DCSDevice
//     var context: DCMGK.GKSensor?
// }


// class DCSCore.StateMachineDefinition {
//     let log: DCSCore.LogProtocol
//     var stateMap: [Swift.String : Swift.AnyObject]
//     var eventMap: [Swift.String : Swift.AnyObject]
//     let version: Swift.Double
//     var activityDefinitions: [Swift.String : DCSCore.ActivityFlowDefinition]?
//     var activityObjects: [Swift.String : DCSCore.StateActivity]?
//     var initialActivity: Swift.String?
//     var errorHandler: Swift.String?
//     var unhandledEventsHandler: Swift.String?
// }


// class DCSCore.DCSDeviceManager {
//     let log: DCSCore.LogProtocol
//     var activeDevices: [Swift.String : DCSCore.DCSDevice]
//     var definitions: [Swift.String : DCSCore.StateMachineDefinition]
//     var modules: [Swift.Int : DCSCore.DeviceControlModuleProtocol]
//     var controllers: [Swift.Int64 : DCSCore.ActivityFlowController]
//     var tagManufacturerMap: [Swift.String : DCSCore.DCMType]
//     var internalDeviceNumber: Swift.Int
//     var dcsStore: DCSCore.IDCSDataStore
// }


// class DCSCore.BlePeripheral {
//     let log: DCSCore.LogProtocol
//     var peripheral: DCSCore.CBPeripheralProtocol?
//     var delegate: DCSCore.BLEPeripheralCallBack?
// }


// class DCSCore.DCSAdaptor {
//     let log: DCSCore.LogProtocol
//     var isInitialized: Swift.Bool
//     var deviceManager: DCSCore.DCSDeviceManager?
//     let debugEnabled: Swift.Bool
//     var adaptorCallback: DCSCore.IDCSCallback?
//     var dcsStore: DCSCore.IDCSDataStore
//     let returnValue: Swift.Int32
//     var dcmTypes: [Swift.Int : DCSCore.DCMType]
//     var eventCancellable: Combine.AnyCancellable?
//     var logCancellable: Combine.AnyCancellable?
// }


// class DCSCore.BleManager {
//     var log: DCSCore.LogProtocol
//     var centralManager: DCSCore.CBCentralManagerProtocol?
//     var hasState: Swift.Bool
//     let kCBCentralRestoreName: Swift.String
//     var wantedRestoredPeripherals: [DCSCore.CBPeripheralProtocol]
//     var bleOffDialogCanBePresented: Swift.Bool
//     var analyteSensors: [Swift.String : (callback: DCSCore.BLECentralCallback, cbPeripheral: DCSCore.CBPeripheralProtocol?)]
//     var scanRequests: Swift.Int
//     var mockPeripheral: DCSCore.MockCBPeripheral?
//     var restoredPeripherals: [__C.CBPeripheral]?
// }


let flowController =  """
{
    "flowControllerVersion": "1.0",
    "controllerType": "DualSensor",
    "initialActivity": "GKSActivityScanSensor",
    "errorHandler": "GKSActivityError",
    "activities": [
        {
            "activity": "GKSActivityScanSensor",
            "eventFlows": [
                {
                    "DCSGKSDeviceFoundEvent": "GKSActivityConnect"
                },
                {
                    "DCSGKSScanError": "_FlowContinue"
                }
            ]
        },
        {
            "activity": "GKSActivityConnect",
            "eventFlows": [
                {
                    "DCSGKSSecuredConnectedEvent": "GKSActivityEnableSecurityNotifications"
                },
                {
                    "DCSGKSConnectedEvent": "GKSActivityEnableNotification"
                }
            ]
        },
        {
            "activity": "GKSActivityEnableSecurityNotifications",
            "eventFlows": [
                {
                    "DCSGKSSecurityNotificationsEnabledEvent": "GKSActivityCheckAuthentication"
                },
                {
                    "DCSGKSRealtimeReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSRetryConnectEvent": "GKSActivityConnect"
                }
            ]
        },
        {
            "activity": "GKSActivityEnableNotification",
            "eventFlows": [
                {
                    "DCSGKSNotificationEnabledEvent": "GKSActivityGetRealtimeReadings"
                },
                {
                    "DCSGKSRealtimeReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSRetryConnectEvent": "GKSActivityConnect"
                }
            ]
        },
        {
            "activity": "GKSActivityCheckAuthentication",
            "eventFlows": [
                {
                    "DCSGKSAuthenticationRequiredEvent": "GKSActivityStartAuthentication"
                },
                {
                    "DCSGKSAuthorizationRequiredEvent": "GKSActivityStartAuthorization"
                }
            ]
        },
        {
            "activity": "GKSActivityStartAuthentication",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityLoadCertificate"
                }
            ]
        },
        {
            "activity": "GKSActivityLoadCertificate",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivitySendCertificate"
                }
            ]
        },
        {
            "activity": "GKSActivitySendCertificate",
            "eventFlows": [
                {
                    "DCSGKSCertificateSentEvent": "GKSActivitySendCertificateLoadDone"
                }
            ]
        },
        {
            "activity": "GKSActivitySendCertificateLoadDone",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityWaitCertificateAcceptance"
                }
            ]
        },
        {
            "activity": "GKSActivityWaitCertificateAcceptance",
            "eventFlows": [
                {
                    "DCSGKSCertificateAcceptedEvent": "GKSActivityGetCertificate"
                }
            ]
        },
        {
            "activity": "GKSActivityGetCertificate",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityWaitCertificateReady"
                }
            ]
        },
        {
            "activity": "GKSActivityWaitCertificateReady",
            "eventFlows": [
                {
                    "DCSGKSCertificateReadyEvent": "GKSActivityReadCertificate"
                }
            ]
        },
        {
            "activity": "GKSActivityReadCertificate",
            "eventFlows": [
                {
                    "DCSGKSCertificateReadEvent": "GKSActivityValidateCertificate"
                }
            ]
        },
        {
            "activity": "GKSActivityValidateCertificate",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivitySendEphemeral"
                }
            ]
        },
        {
            "activity": "GKSActivitySendEphemeral",
            "eventFlows": [
                {
                    "DCSGKSCertificateSentEvent": "GKSActivitySendEphemeralDone"
                }
            ]
        },
        {
            "activity": "GKSActivitySendEphemeralDone",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityPatchEphemeralWait"
                }
            ]
        },
        {
            "activity": "GKSActivityPatchEphemeralWait",
            "eventFlows": [
                {
                    "DCSGKSEphemeralReadyEvent": "GKSActivityReadPatchEphemeral"
                }
            ]
        },
        {
            "activity": "GKSActivityReadPatchEphemeral",
            "eventFlows": [
                {
                    "DCSGKSCertificateReadEvent": "GKSActivityFinalizeAuthentication"
                }
            ]
        },
        {
            "activity": "GKSActivityFinalizeAuthentication",
            "eventFlows": [
                {
                    "DCSGKSECDHCompleteEvent": "GKSActivityStartAuthorization"
                }
            ]
        },
        {
            "activity": "GKSActivityStartAuthorization",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityWaitChallengeLoad"
                }
            ]
        },
        {
            "activity": "GKSActivityWaitChallengeLoad",
            "eventFlows": [
                {
                    "DCSGKSChallengeLoadDoneEvent": "GKSActivityReadR1"
                }
            ]
        },
        {
            "activity": "GKSActivityReadR1",
            "eventFlows": [
                {
                    "DCSGKSChallengeDataReadEvent": "GKSActivitySendChallengeResponse"
                }
            ]
        },
        {
            "activity": "GKSActivitySendChallengeResponse",
            "eventFlows": [
                {
                    "DCSGKSChallengeDataSentEvent": "GKSActivitySendChallengeLoadDone"
                }
            ]
        },
        {
            "activity": "GKSActivitySendChallengeLoadDone",
            "eventFlows": [
                {
                    "DCSGKSCommandSentEvent": "GKSActivityWaitPatchChallengeLoadDone"
                }
            ]
        },
        {
            "activity": "GKSActivityWaitPatchChallengeLoadDone",
            "eventFlows": [
                {
                    "DCSGKSChallengeLoadDoneEvent": "GKSActivityReadPatchChallengeResponse"
                }
            ]
        },
        {
            "activity": "GKSActivityReadPatchChallengeResponse",
            "eventFlows": [
                {
                    "DCSGKSChallengeDataReadEvent": "GKSActivityFinalizeAuthorization"
                }
            ]
        },
        {
            "activity": "GKSActivityFinalizeAuthorization",
            "eventFlows": [
                {
                    "DCSGKSRealtimeReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSNotificationEnabledEvent": "GKSActivityGetRealtimeReadings"
                }
            ]
        },
        {
            "activity": "GKSActivityGetRealtimeReadings",
            "eventFlows": [
                {
                    "DCSGKSRealtimeReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSHistoricalReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSHistoricalReadingEndEvent": "_FlowContinue"
                },
                {
                    "DCSGKSFastDataEvent": "_FlowContinue"
                },
                {
                    "DCSGKSRetryConnectEvent": "GKSActivityConnect"
                }
            ]
        },
        {
            "activity": "GKSActivityError",
            "eventFlows": [
                {
                    "DCSGKSDisconnectEvent": "GKSActivityConnect"
                },
                {
                    "DCSGKSSecurityErrorEvent": "GKSActivityDisconnect"
                },
                {
                    "DCSGKSConnectTimedOutEvent": "GKSActivityScanSensor"
                }
            ]
        },
        {
            "activity": "GKSActivityDisconnect",
            "eventFlows": [
                {
                    "DCSGKSRetryConnectEvent": "GKSActivityConnect"
                }
            ]
        },
        {
            "activity": "GKSActivityCloseDevice",
            "eventFlows": [
                {
                    "DCSGKSRetryConnectEvent": "GKSActivityConnect"
                }
            ]
        },
        {
            "activity": "GKSActivityGetEventLog",
            "eventFlows": [
                {
                    "DCSGKSHistoricalReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSRealtimeReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSFactoryDataEvent": "_FlowContinue"
                },
                {
                    "DCSGKSHistoricalReadingEvent": "_FlowContinue"
                },
                {
                    "DCSGKSHistoricalReadingEndEvent": "_FlowContinue"
                },
                {
                    "DCSGKSEventLogEvent": "_FlowContinue"
                },
                {
                    "DCSGKSFastDataEvent": "_FlowContinue"
                },
                {
                    "DCSGKSEventLogEndEvent": "GKSActivityGetRealtimeReadings"
                }
            ]
        }
    ]
}
"""
