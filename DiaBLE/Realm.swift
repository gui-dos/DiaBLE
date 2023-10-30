import Foundation
import RealmSwift

class AlarmConfigEntity: Object {
    @objc dynamic var _alarmType: Int = 0
    @objc dynamic var _id: Int = 0
    @objc dynamic var _enabled: Bool = false
    @objc dynamic var _threshold: Double = 0
    @objc dynamic var _soundType: Int = 0
    @objc dynamic var _soundSetting: String = ""
    @objc dynamic var _tolerance: Double = 0
    @objc dynamic var _f_high: Double = 0
    @objc dynamic var _overrideDND: Bool = false

    override static func primaryKey() -> String? {
        return "_alarmType"
    }
}

class AppConfigEntity: Object {
    @objc dynamic var _configName: String = ""
    @objc dynamic var _id: Int = 0
    @objc dynamic var _configType: Int = 0
    @objc dynamic var _configValue: String = ""
    @objc dynamic var _source: Int = 0                // ConfigSource 1: build, 2: runtime

    override static func primaryKey() -> String? {
        return "_configName"
    }

    // TODO

    /// [_configName]
    static let keys = [
        ["_libreviewAccountIdKey_"],
        ["_libreviewDateOfBirthKey_"],
        ["_libreviewDidAcceptCRMAgreement_"],
        ["_libreviewEmailKey_"],
        ["_libreviewFirstNameKey_"],
        ["_libreviewLastNameKey_"],
        ["_libreviewMinorRuleKey_"],
        ["_libreviewTransitionableSensorSerialNumberKey_"],
        ["_libreviewUserNameKey_"],
        ["_libreviewUserTokenKey_"],
        ["_NEWYU_STATUS_20_TIMESTAMP_KEY_"],
        ["_pending_sensor_upload_"],
        ["acceptedHIPAAAuthLanguage"],
        ["acceptedPhoneWarningsLanguage"],
        ["acceptedPhoneWarningsVersion"],
        ["acceptedPrivacyNoticeLanguage"],
        ["acceptedPrivacyNoticeVersion"],
        ["acceptedTermsOfUseLanguage"],
        ["acceptedTermsOfUseVersion"],
        ["AMSensorWarmupCompleteEvent"],
        ["appAssets"],
        ["appDefaultServingSize"],
        ["appEnvironmentKey"],
        ["appMinimumAge"],
        ["appProductStandardNumber"],
        ["appRegistrationNumber"],
        ["appVersionAssetDownloadedKey"],
        ["appVersionStringWhenSetKey"],
        ["AUBannerNotificationsEnabled"],
        ["AUBluetoothIsEnabled"],
        ["AUCriticalAlertEnabled"],
        ["AUFixedLowGlucoseIsEnabled"],
        ["AUFixedLowGlucoseOverrideDND"],
        ["AUHighGlucoseIsEnabled"],
        ["AUHighGlucoseOverrideDND"],
        ["AULockScreenNotificationsEnabled"],
        ["AULowGlucoseIsEnabled"],
        ["AULowGlucoseOverrideDND"],
        ["AUNotificationsAreEnabled"],
        ["AUNotificationSoundsEnabled"],
        ["AUOSCompatibilityStatus"],
        ["AUSignalLossGlucoseIsEnabled"],
        ["AUSignalLossGlucoseOverrideDND"],
        ["AUSignalLossStatus"],
        ["deviceAddress"],
        ["didAcceptHIPAAAuth"],
        ["didAcceptPhoneWarnings"],
        ["didAcceptPrivacyNotice"],
        ["didAcceptTermsOfUse"],
        ["didAllowCriticalAlertsPermission"],
        ["didSeeAlarmsAudioExplanation"],
        ["didSeeAlarmsTutorial2"],
        ["didSeeAlarmsTutorial4"],
        ["didSeeAlarmsTutorial5"],
        ["didSeeCarbohydrateUnits"],
        ["didSeeContinousGlucoseReadings"],
        ["didSeeCriticalAlertsPermission"],
        ["didSeeGlucoseBackgroundColorExplanation"],
        ["didSeeResultsScreenExplanation"],
        ["didSeeTargetGlucoseRange"],
        ["didSeeTrendArrowsExplanation"],
        ["didSeeTutorialWelcomeScreen"],
        ["didSeeUnitsOfMeasure"],
        ["didSeeVitaminCWarningScreen"],
        ["didTreatmentDecisions1Explanation"],
        ["didTreatmentDecisions2Explanation"],
        ["firstConnect"],
        ["firstTimeAlarmsAccess"],
        ["firstTimeTurnOnGlucoseAlarm"],
        ["highGlucoseAlarmTone"],
        ["highGlucoseAlarmValue"],
        ["hipaa_status"],
        ["installationId"],
        ["isHighGlucoseAlarmOn"],
        ["isLowGlucoseAlarmOn"],
        ["isSignalLossAlarmOn"],
        ["isTextToSpeechOn"],
        ["kUnavailable_Alarm_Can_Be_Presented"],
        ["LAST_SL_LOG_UPDATE_TIMESTAMP"],
        ["lastEventReceived"],
        ["lastUpdateCheckTimestamp"],
        ["lastUpdateCheckTimestampPhoneWarnings"],
        ["latestPhoneWarningsVersion"],
        ["latestPrivacyNoticeVersion"],
        ["latestTermsOfUseVersion"],
        ["Libre3WrappedKAuth"],                      // 149 bytes hex
        ["lowGlucoseAlarmTone"],
        ["lowGlucoseAlarmValue"],
        ["newYuApiKey"],
        ["newYuDomain"],
        ["newYuGateway"],
        ["newYuShareUrl"],
        ["newYuUrl"],
        ["oneStepAudience"],
        ["oneStepBaseUrl"],
        ["oneStepIssuer"],
        ["oneStepSubject"],
        ["rwe_status"],
        ["sandboxUrl"],
        ["signalLossAlarmTone"],
        ["SignalLossDateTime_"],
        ["SignalLossDateTime_1"],
        ["SignalLossDateTime_2"],
        ["SignalLossDateTime_3"],
        ["SignalLossDateTime_4"],
        ["SignalLossDateTime_5"],
        ["SignalLossDateTime_6"],
        ["SignalLossEndDateTime"],
        ["SignalLossScheduleCount"],
        ["SignalLossUserDismissTime"],
        ["startSensorVideoUrl"],
        ["userAccountMode"],                         // UserAccountType string
        ["userCarbUnit"],
        ["userGlucoseUnit"],
        ["userGramsPerServing"],
        ["userMaxGlucoseRange"],
        ["userMinGlucoseRange"]
    ]

}

class AppEventEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _eventType: Int = 0
    @objc dynamic var _eventErrorCode: Int = 0       // DPCRLInterface
    @objc dynamic var _timestampUTC: Int = 0
    @objc dynamic var _timestampLocal: Int = 0
    @objc dynamic var _timeZone: String = ""
    @objc dynamic var _eventParams: String = ""
    @objc dynamic var _eventData: String = ""
    @objc dynamic var _display: Bool = false

    override static func primaryKey() -> String? {
        return "_id"
    }

    override static func indexedProperties() -> [String] {
        return ["_eventType", "_eventErrorCode", "_timestampUTC", "_timeZone"]
    }
}

class GlucoseReadingEntity: Object {
    @objc dynamic var _compositeKey: Int = 0         // _sensor._id << 32 + _lifeCount
    @objc dynamic var _id: Int = 0
    @objc dynamic var _sensor: SensorEntity?
    @objc dynamic var _lifeCount: Int = 0
    @objc dynamic var _timestampUTC: Int = 0
    @objc dynamic var _timestampLocal: Int = 0
    @objc dynamic var _timeZone: String = ""
    @objc dynamic var _currentGlucose: Double = 0
    @objc dynamic var _uncappedGlucose: Double = 0
    @objc dynamic var _historicGlucose: Double = 0
    @objc dynamic var _trend: Int = 0
    @objc dynamic var _rateOfChange: Double = 0
    @objc dynamic var _dqFlag: Int = 0
    @objc dynamic var _historicDqFlag: Int = 0
    @objc dynamic var _actionable: Int = 0
    @objc dynamic var _sensorCondition: Int = 0
    @objc dynamic var _esaDuration: Int = 0
    @objc dynamic var _alarmPresentFlag: Int = 0
    @objc dynamic var _alarmRemoveFlag: Int = 0
    @objc dynamic var _alarmEpisodeFlag: Int = 0
    @objc dynamic var _glycemicAlarmStatus: Int = 0
    @objc dynamic var _projectedGlucose: Double = 0
    @objc dynamic var _resultRange: Int = 0
    let _notes = List<NotesEntity>()
    @objc dynamic var _temperature: Int = 0
    @objc dynamic var _rawData: String = ""          // 8 bytes hex
    @objc dynamic var _viewed: Bool = false
    @objc dynamic var _extendedUDOflag: Int = 0
    @objc dynamic var _rssi: Int = 0
    @objc dynamic var _isWarmup: Bool = false
    @objc dynamic var _uncappedHistoric: Double = 0
    @objc dynamic var _userResultRange: Int = 0
    let _stateMap = List<Int>()
    @objc dynamic var _isHistoric: Bool = false

    override static func primaryKey() -> String? {
        return "_compositeKey"
    }

    override static func indexedProperties() -> [String] {
        return ["_id", "_lifeCount", "_timestampUTC", "_timestampLocal"]
    }
}

class NoteElementEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _noteType: Int = 0
    @objc dynamic var _subType: Int = 0
    @objc dynamic var _value: Double = 0
    @objc dynamic var _servingSize: Double = 0

    override static func primaryKey() -> String? {
        return "_id"
    }
}

class NotesEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _timestampUTC: Int = 0
    @objc dynamic var _timestampLocal: Int = 0
    @objc dynamic var _timeZone: String = ""
    @objc dynamic var _comment: String? = nil
    @objc dynamic var _glucoseReading: GlucoseReadingEntity?
    let _noteElements = List<NoteElementEntity>()
    @objc dynamic var _isDeleted: Bool = false

    override static func primaryKey() -> String? {
        return "_id"
    }
}

class ReminderEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _reminderType: Int = 0
    @objc dynamic var _enabled: Bool = false
    @objc dynamic var _reminderCode: Int = 0
    @objc dynamic var _repeatType: Int = 0
    @objc dynamic var _description: String = ""
    @objc dynamic var _interval: Int = 0
    @objc dynamic var _intervalType: Int = 0
    @objc dynamic var _createdTime: Int = 0
    @objc dynamic var _timeZone: String = ""

    override static func primaryKey() -> String? {
        return "_id"
    }
}

class SensorEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _serialNumber: String = ""
    @objc dynamic var _sensorUID: String = ""        // BLE address hex
    @objc dynamic var _productType: Int = 0
    @objc dynamic var _localization: Int = 0
    @objc dynamic var _generation: Int = 0
    @objc dynamic var _hwVersion: String = ""
    @objc dynamic var _swVersion: String = ""
    @objc dynamic var _fwVersion: String = ""
    @objc dynamic var _activationDateUtc: Int = 0
    @objc dynamic var _blePIN: String = ""
    @objc dynamic var _warmupDuration: Int = 0
    @objc dynamic var _wearDuration: Int = 0
    @objc dynamic var _currentLifeCount: Int = 0
    @objc dynamic var _lastHistoricReading: Int = 0  // a lifeCount
    @objc dynamic var _status: Int = 0
    @objc dynamic var _receiverID: Int = 0
    @objc dynamic var _factoryData: String = ""      // 148 bytes hex (final CRC)
    @objc dynamic var _securityVersion: Int = 0
    @objc dynamic var _lastEvent: Int = 0

    override static func primaryKey() -> String? {
        return "_id"
    }
}

class SensorEventEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _sensor: SensorEntity?
    @objc dynamic var _lifeCount: Int = 0
    @objc dynamic var _timestampUTC: Int = 0
    @objc dynamic var _eventCode: Int = 0           // SensorEventType
    @objc dynamic var _eventValue: Double = 0       // same SensorEventType

    override static func primaryKey() -> String? {
        return "_id"
    }
}

class SequenceEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _nextSensorId: Int = 0
    @objc dynamic var _nextGlucoseReadingId: Int = 0
    @objc dynamic var _nextSensorEventId: Int = 0
    @objc dynamic var _nextNoteId: Int = 0
    @objc dynamic var _nextNoteElementId: Int = 0
    @objc dynamic var _nextAppConfigId: Int = 0
    @objc dynamic var _nextAppEventId: Int = 0
    @objc dynamic var _nextAlarmConfigId: Int = 0
    @objc dynamic var _nextReminderId: Int = 0
    @objc dynamic var _nextUploadQueueId: Int = 0
}

class UploadQueueRecordEntity: Object {
    @objc dynamic var _id: Int = 0
    @objc dynamic var _recordNumber: Int = 0
    @objc dynamic var _recordType: String = ""

    override static func primaryKey() -> String? {
        return "_id"
    }
}


// TODO: verify raw values

extension Libre3 {

    enum UserAccountType {
        case accountUser
        case accountLess
        case accountEmpty
        case accountSwitched
        case accountNotDefined
    }

    enum ConfigSource: Int {
        case build    = 1
        case runtime  = 2
    }

    enum LifeState: Int {
        case missing         = 1
        case warmup          = 2
        case ready           = 3
        case expired         = 4
        case active          = 5
        case ended           = 6
        case insertionFailed = 7
    }

    enum AppEventType: Int {
        case none                = 0
        case bleConnect          = 1
        case bleDisconnect       = 2
        case alarmConfigChanged  = 3
        case alarmStateChanged
        case error
        // Android:
        //   Error(4),
        //   PATCH_WARMUP(5),
        //   PATCH_PAIRED(6),
        //   PATCH_ENDED(7),
        //   FIRST_INIT(8),
        //   LOGGED_IN(9),
        //   NO_PATCH(10),
        //   BleDataCountLow(11),
        //   BleDisconnectsHigh(12),
        //   AppException(13),
        //   AlarmStateChanged(14);
    }

    enum EventType: Int {
        case sensorException      = 0
        case newYuUploadFailure   = 1
        case oneStepUploadFailure = 2
        case AppException         = 3
        //   SensorScanUdoLogError(4);
    }

    enum SensorEventType: Int {
        case none         = 0
        case activated    = 1
        case connected    = 2
        case disconnected = 3
        case expired      = 4
        case terminated   = 5
        case error        = 6
        // Android:
        //   NONE(0),
        //   WARMINGUP(1),
        //   ACTIVATED(2),
        //   CONNECTED(3),
        //   DISCONNECTED(4),
        //   ENDED(5),
        //   EXPIRED(6),
        //   TERMINATED(7),
        //   ERROR(8);

    }

    // same as App's GlycemicAlarm
    enum GlycemicAlarmStatus: Int {
        case alarmNotDetermined   = 0
        case lowGlucose           = 1
        case projectedLowGlucose  = 2
        case normalGlucose        = 3
        case projectedHighGlucose = 4
        case highGlucose          = 5
    }

    enum AlarmFlag {
        case lowAlarm
        case highAlarm
        case urgentLowAlarm
        case signalLossAlarm
    }

    struct GlucoseAlarmState {
        var isPresented: Bool
        var isInEpisode: Bool
        var isDismissed: Bool
        var isCleared: Bool
        var isUserCleared: Bool
    }

    struct SignalLossAlarmState {
        var isPresented: Bool
        var isCleared: Bool
        var isUserCleared: Bool
        var isAutoDismissed: Bool
        var isUserDismissed: Bool
    }

    struct AlarmStates {
        let lowGlucose: GlucoseAlarmState
        let highGlucose: GlucoseAlarmState
        let fixedLowGlucose: GlucoseAlarmState
        let signalLoss: SignalLossAlarmState
    }

    struct AlarmStateDictionary {
        let episodeFlag: Int
        var states: AlarmStates
    }

    // TODO: lowGucoseAlarm, highGlucoseAlarm, fixedLowAlarm, signalLossAlarm JSON decoding when eventType = 4


    static let RealmEntityNames = [
        "AlarmConfigEntity",
        "AppConfigEntity",
        "AppEventEntity",
        "GlucoseReadingEntity",
        "NoteElementEntity",
        "NotesEntity",
        "ReminderEntity",
        "SensorEntity",
        "SensorEventEntity",
        "SequenceEntity",
        "UploadQueueRecordEntity"
    ]


    // class Libre3.AlarmConfigEntity {
    //     var _id: Swift.Int32
    //     var _alarmType: Swift.Int32
    //     var _enabled: Swift.Bool
    //     var _threshold: Swift.Double
    //     var _soundType: Swift.Int32
    //     var _soundSetting: Swift.String
    //     var _tolerance: Swift.Double
    //     var _f_high: Swift.Double
    //     var _overrideDND: Swift.Bool
    // }


    // class Libre3.AppConfigEntity {
    //     var _id: Swift.Int32
    //     var _configName: Swift.String
    //     var _configType: Swift.Int32
    //     var _configValue: Swift.String
    //     var _source: Swift.Int32
    // }


    // class Libre3.AppEventEntity {
    //     var _id: Swift.Int32
    //     var _eventType: Swift.Int32
    //     var _eventErrorCode: Swift.Int32
    //     var _timestampUTC: Swift.Int64
    //     var _timestampLocal: Swift.Int64
    //     var _timeZone: Swift.String
    //     var _eventParams: Swift.String
    //     var _eventData: Swift.String
    //     var _display: Swift.Bool
    // }


    // class Libre3.GlucoseReadingEntity {
    //     var _id: Swift.Int32
    //     var _sensor: Libre3.SensorEntity?
    //     var _lifeCount: Swift.Int32
    //     var _timestampUTC: Swift.Int64
    //     var _timestampLocal: Swift.Int64
    //     var _timeZone: Swift.String
    //     var _currentGlucose: Swift.Double
    //     var _uncappedGlucose: Swift.Double
    //     var _historicGlucose: Swift.Double
    //     var _trend: Swift.Int32
    //     var _rateOfChange: Swift.Double
    //     var _dqFlag: Swift.Int32
    //     var _historicDqFlag: Swift.Int32
    //     var _actionable: Swift.Int32
    //     var _sensorCondition: Swift.Int32
    //     var _esaDuration: Swift.Int32
    //     var _alarmPresentFlag: Swift.Int16
    //     var _alarmRemoveFlag: Swift.Int16
    //     var _alarmEpisodeFlag: Swift.Int16
    //     var _glycemicAlarmStatus: Swift.Int32
    //     var _projectedGlucose: Swift.Double
    //     var _resultRange: Swift.Int32
    //     var _notes: RealmSwift.List<Libre3.NotesEntity>
    //     var _temperature: Swift.Int32
    //     var _rawData: Swift.String
    //     var _viewed: Swift.Bool
    //     var _extendedUDOflag: Swift.Int16
    //     var _rssi: Swift.Int32
    //     var _isWarmup: Swift.Bool
    //     var _uncappedHistoric: Swift.Double
    //     var _userResultRange: Swift.Int32
    //     var _compositeKey: Swift.Int64
    //     var _stateMap: RealmSwift.List<Swift.Int8>
    //     var _isHistoric: Swift.Bool
    // }


    // class Libre3.NoteElementEntity {
    //     var _id: Swift.Int32
    //     var _noteType: Libre3.NoteItemType
    //     var _subType: Swift.Int32
    //     var _value: Swift.Double
    //     var _servingSize: Swift.Double
    // }


    // class Libre3.NotesEntity {
    //     var _id: Swift.Int32
    //     var _timestampUTC: Swift.Int64
    //     var _timestampLocal: Swift.Int64
    //     var _timeZone: Swift.String
    //     var _comment: Swift.String?
    //     var _glucoseReading: Libre3.GlucoseReadingEntity?
    //     var _noteElements: RealmSwift.List<Libre3.NoteElementEntity>
    //     var _isDeleted: Swift.Bool
    //     var reading: Libre3.Reading?
    //     let glucoseReading: RealmSwift.LinkingObjects<Libre3.GlucoseReadingEntity>
    // }


    // class Libre3.ReminderEntity {
    //     var _id: Swift.Int32
    //     var _reminderType: Swift.Int32
    //     var _enabled: Swift.Bool
    //     var _reminderCode: Swift.Int32
    //     var _repeatType: Swift.Int32
    //     var _description: Swift.String
    //     var _interval: Swift.Int32
    //     var _intervalType: Swift.Int32
    //     var _createdTime: Swift.Int64
    //     var _timeZone: Swift.String
    // }


    // class Libre3.SensorEntity {
    //     var _id: Swift.Int32
    //     var _serialNumber: Swift.String
    //     var _sensorUID: Swift.String
    //     var _productType: Swift.Int32
    //     var _localization: Swift.Int32
    //     var _generation: Swift.Int32
    //     var _hwVersion: Swift.String
    //     var _swVersion: Swift.String
    //     var _fwVersion: Swift.String
    //     var _activationDateUtc: Swift.Int64
    //     var _blePIN: Swift.String
    //     var _warmupDuration: Swift.Int32
    //     var _wearDuration: Swift.Int32
    //     var _currentLifeCount: Swift.Int32
    //     var _lastHistoricReading: Swift.Int32
    //     var _status: Swift.Int32
    //     var _receiverID: Swift.Int64
    //     var _factoryData: Swift.String
    //     var _securityVersion: Swift.Int32
    //     var _lastEvent: Swift.Int32
    // }


    // class Libre3.SensorEventEntity {
    //     var _id: Swift.Int32
    //     var _sensor: Libre3.SensorEntity?
    //     var _lifeCount: Swift.Int32
    //     var _timestampUTC: Swift.Int64
    //     var _eventCode: Swift.Int32
    //     var _eventValue: Swift.Double
    // }


    // class Libre3.SequenceEntity {
    //     var _id: Swift.Int32
    //     var _nextSensorId: Swift.Int32
    //     var _nextGlucoseReadingId: Swift.Int32
    //     var _nextSensorEventId: Swift.Int32
    //     var _nextNoteId: Swift.Int32
    //     var _nextNoteElementId: Swift.Int32
    //     var _nextAppConfigId: Swift.Int32
    //     var _nextAppEventId: Swift.Int32
    //     var _nextAlarmConfigId: Swift.Int32
    //     var _nextReminderId: Swift.Int32
    //     var _nextUploadQueueId: Swift.Int32
    // }


    // class Libre3.UploadQueueRecordEntity {
    //     var _id: Swift.Int32
    //     var _recordNumber: Swift.Int64
    //     var _recordType: Swift.String
    // }


    // TODO: parse flatted JSON: https://github.com/WebReflection/flatted

    func parseRealmFlattedJson(data: Data) {
        // var index = 0
        if let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let entities = (json[0] as! [String: String]).sorted { Int($0.value)! < Int($1.value)! }
            log("Realm: trident.json tables: \(entities)")
            for (i, e) in entities.enumerated() {
                let indexes = (json[i + 1] as! [String])
                log("\(e.key): \(indexes.count) rows, indexes: \(indexes.first ?? "0") - \(indexes.last ?? "0")")
            }
        }
    }

}
