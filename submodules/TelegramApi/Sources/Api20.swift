public extension Api {
    enum PhoneCall: TypeConstructorDescription {
        public class Cons_phoneCall: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var date: Int32
            public var adminId: Int64
            public var participantId: Int64
            public var gAOrB: Buffer
            public var keyFingerprint: Int64
            public var `protocol`: Api.PhoneCallProtocol
            public var connections: [Api.PhoneConnection]
            public var startDate: Int32
            public var customParameters: Api.DataJSON?
            public init(flags: Int32, id: Int64, accessHash: Int64, date: Int32, adminId: Int64, participantId: Int64, gAOrB: Buffer, keyFingerprint: Int64, `protocol`: Api.PhoneCallProtocol, connections: [Api.PhoneConnection], startDate: Int32, customParameters: Api.DataJSON?) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.date = date
                self.adminId = adminId
                self.participantId = participantId
                self.gAOrB = gAOrB
                self.keyFingerprint = keyFingerprint
                self.`protocol` = `protocol`
                self.connections = connections
                self.startDate = startDate
                self.customParameters = customParameters
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCall", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("date", ConstructorParameterDescription(self.date)), ("adminId", ConstructorParameterDescription(self.adminId)), ("participantId", ConstructorParameterDescription(self.participantId)), ("gAOrB", ConstructorParameterDescription(self.gAOrB)), ("keyFingerprint", ConstructorParameterDescription(self.keyFingerprint)), ("`protocol`", ConstructorParameterDescription(self.`protocol`)), ("connections", ConstructorParameterDescription(self.connections)), ("startDate", ConstructorParameterDescription(self.startDate)), ("customParameters", ConstructorParameterDescription(self.customParameters))])
            }
        }
        public class Cons_phoneCallAccepted: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var date: Int32
            public var adminId: Int64
            public var participantId: Int64
            public var gB: Buffer
            public var `protocol`: Api.PhoneCallProtocol
            public init(flags: Int32, id: Int64, accessHash: Int64, date: Int32, adminId: Int64, participantId: Int64, gB: Buffer, `protocol`: Api.PhoneCallProtocol) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.date = date
                self.adminId = adminId
                self.participantId = participantId
                self.gB = gB
                self.`protocol` = `protocol`
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallAccepted", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("date", ConstructorParameterDescription(self.date)), ("adminId", ConstructorParameterDescription(self.adminId)), ("participantId", ConstructorParameterDescription(self.participantId)), ("gB", ConstructorParameterDescription(self.gB)), ("`protocol`", ConstructorParameterDescription(self.`protocol`))])
            }
        }
        public class Cons_phoneCallDiscarded: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var reason: Api.PhoneCallDiscardReason?
            public var duration: Int32?
            public init(flags: Int32, id: Int64, reason: Api.PhoneCallDiscardReason?, duration: Int32?) {
                self.flags = flags
                self.id = id
                self.reason = reason
                self.duration = duration
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallDiscarded", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("reason", ConstructorParameterDescription(self.reason)), ("duration", ConstructorParameterDescription(self.duration))])
            }
        }
        public class Cons_phoneCallEmpty: TypeConstructorDescription {
            public var id: Int64
            public init(id: Int64) {
                self.id = id
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallEmpty", [("id", ConstructorParameterDescription(self.id))])
            }
        }
        public class Cons_phoneCallRequested: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var date: Int32
            public var adminId: Int64
            public var participantId: Int64
            public var gAHash: Buffer
            public var `protocol`: Api.PhoneCallProtocol
            public init(flags: Int32, id: Int64, accessHash: Int64, date: Int32, adminId: Int64, participantId: Int64, gAHash: Buffer, `protocol`: Api.PhoneCallProtocol) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.date = date
                self.adminId = adminId
                self.participantId = participantId
                self.gAHash = gAHash
                self.`protocol` = `protocol`
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallRequested", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("date", ConstructorParameterDescription(self.date)), ("adminId", ConstructorParameterDescription(self.adminId)), ("participantId", ConstructorParameterDescription(self.participantId)), ("gAHash", ConstructorParameterDescription(self.gAHash)), ("`protocol`", ConstructorParameterDescription(self.`protocol`))])
            }
        }
        public class Cons_phoneCallWaiting: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var date: Int32
            public var adminId: Int64
            public var participantId: Int64
            public var `protocol`: Api.PhoneCallProtocol
            public var receiveDate: Int32?
            public init(flags: Int32, id: Int64, accessHash: Int64, date: Int32, adminId: Int64, participantId: Int64, `protocol`: Api.PhoneCallProtocol, receiveDate: Int32?) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.date = date
                self.adminId = adminId
                self.participantId = participantId
                self.`protocol` = `protocol`
                self.receiveDate = receiveDate
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallWaiting", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("date", ConstructorParameterDescription(self.date)), ("adminId", ConstructorParameterDescription(self.adminId)), ("participantId", ConstructorParameterDescription(self.participantId)), ("`protocol`", ConstructorParameterDescription(self.`protocol`)), ("receiveDate", ConstructorParameterDescription(self.receiveDate))])
            }
        }
        case phoneCall(Cons_phoneCall)
        case phoneCallAccepted(Cons_phoneCallAccepted)
        case phoneCallDiscarded(Cons_phoneCallDiscarded)
        case phoneCallEmpty(Cons_phoneCallEmpty)
        case phoneCallRequested(Cons_phoneCallRequested)
        case phoneCallWaiting(Cons_phoneCallWaiting)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .phoneCall(let _data):
                if boxed {
                    buffer.appendInt32(810769141)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                serializeInt64(_data.adminId, buffer: buffer, boxed: false)
                serializeInt64(_data.participantId, buffer: buffer, boxed: false)
                serializeBytes(_data.gAOrB, buffer: buffer, boxed: false)
                serializeInt64(_data.keyFingerprint, buffer: buffer, boxed: false)
                _data.`protocol`.serialize(buffer, true)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.connections.count))
                for item in _data.connections {
                    item.serialize(buffer, true)
                }
                serializeInt32(_data.startDate, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 7) != 0 {
                    _data.customParameters!.serialize(buffer, true)
                }
                break
            case .phoneCallAccepted(let _data):
                if boxed {
                    buffer.appendInt32(912311057)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                serializeInt64(_data.adminId, buffer: buffer, boxed: false)
                serializeInt64(_data.participantId, buffer: buffer, boxed: false)
                serializeBytes(_data.gB, buffer: buffer, boxed: false)
                _data.`protocol`.serialize(buffer, true)
                break
            case .phoneCallDiscarded(let _data):
                if boxed {
                    buffer.appendInt32(1355435489)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.reason!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeInt32(_data.duration!, buffer: buffer, boxed: false)
                }
                break
            case .phoneCallEmpty(let _data):
                if boxed {
                    buffer.appendInt32(1399245077)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                break
            case .phoneCallRequested(let _data):
                if boxed {
                    buffer.appendInt32(347139340)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                serializeInt64(_data.adminId, buffer: buffer, boxed: false)
                serializeInt64(_data.participantId, buffer: buffer, boxed: false)
                serializeBytes(_data.gAHash, buffer: buffer, boxed: false)
                _data.`protocol`.serialize(buffer, true)
                break
            case .phoneCallWaiting(let _data):
                if boxed {
                    buffer.appendInt32(-987599081)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                serializeInt64(_data.adminId, buffer: buffer, boxed: false)
                serializeInt64(_data.participantId, buffer: buffer, boxed: false)
                _data.`protocol`.serialize(buffer, true)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeInt32(_data.receiveDate!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .phoneCall(let _data):
                return ("phoneCall", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("date", ConstructorParameterDescription(_data.date)), ("adminId", ConstructorParameterDescription(_data.adminId)), ("participantId", ConstructorParameterDescription(_data.participantId)), ("gAOrB", ConstructorParameterDescription(_data.gAOrB)), ("keyFingerprint", ConstructorParameterDescription(_data.keyFingerprint)), ("`protocol`", ConstructorParameterDescription(_data.`protocol`)), ("connections", ConstructorParameterDescription(_data.connections)), ("startDate", ConstructorParameterDescription(_data.startDate)), ("customParameters", ConstructorParameterDescription(_data.customParameters))])
            case .phoneCallAccepted(let _data):
                return ("phoneCallAccepted", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("date", ConstructorParameterDescription(_data.date)), ("adminId", ConstructorParameterDescription(_data.adminId)), ("participantId", ConstructorParameterDescription(_data.participantId)), ("gB", ConstructorParameterDescription(_data.gB)), ("`protocol`", ConstructorParameterDescription(_data.`protocol`))])
            case .phoneCallDiscarded(let _data):
                return ("phoneCallDiscarded", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("reason", ConstructorParameterDescription(_data.reason)), ("duration", ConstructorParameterDescription(_data.duration))])
            case .phoneCallEmpty(let _data):
                return ("phoneCallEmpty", [("id", ConstructorParameterDescription(_data.id))])
            case .phoneCallRequested(let _data):
                return ("phoneCallRequested", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("date", ConstructorParameterDescription(_data.date)), ("adminId", ConstructorParameterDescription(_data.adminId)), ("participantId", ConstructorParameterDescription(_data.participantId)), ("gAHash", ConstructorParameterDescription(_data.gAHash)), ("`protocol`", ConstructorParameterDescription(_data.`protocol`))])
            case .phoneCallWaiting(let _data):
                return ("phoneCallWaiting", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("date", ConstructorParameterDescription(_data.date)), ("adminId", ConstructorParameterDescription(_data.adminId)), ("participantId", ConstructorParameterDescription(_data.participantId)), ("`protocol`", ConstructorParameterDescription(_data.`protocol`)), ("receiveDate", ConstructorParameterDescription(_data.receiveDate))])
            }
        }

        public static func parse_phoneCall(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int64?
            _5 = reader.readInt64()
            var _6: Int64?
            _6 = reader.readInt64()
            var _7: Buffer?
            _7 = parseBytes(reader)
            var _8: Int64?
            _8 = reader.readInt64()
            var _9: Api.PhoneCallProtocol?
            if let signature = reader.readInt32() {
                _9 = Api.parse(reader, signature: signature) as? Api.PhoneCallProtocol
            }
            var _10: [Api.PhoneConnection]?
            if let _ = reader.readInt32() {
                _10 = Api.parseVector(reader, elementSignature: 0, elementType: Api.PhoneConnection.self)
            }
            var _11: Int32?
            _11 = reader.readInt32()
            var _12: Api.DataJSON?
            if Int(_1!) & Int(1 << 7) != 0 {
                if let signature = reader.readInt32() {
                    _12 = Api.parse(reader, signature: signature) as? Api.DataJSON
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = _8 != nil
            let _c9 = _9 != nil
            let _c10 = _10 != nil
            let _c11 = _11 != nil
            let _c12 = (Int(_1!) & Int(1 << 7) == 0) || _12 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 && _c9 && _c10 && _c11 && _c12 {
                return Api.PhoneCall.phoneCall(Cons_phoneCall(flags: _1!, id: _2!, accessHash: _3!, date: _4!, adminId: _5!, participantId: _6!, gAOrB: _7!, keyFingerprint: _8!, protocol: _9!, connections: _10!, startDate: _11!, customParameters: _12))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallAccepted(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int64?
            _5 = reader.readInt64()
            var _6: Int64?
            _6 = reader.readInt64()
            var _7: Buffer?
            _7 = parseBytes(reader)
            var _8: Api.PhoneCallProtocol?
            if let signature = reader.readInt32() {
                _8 = Api.parse(reader, signature: signature) as? Api.PhoneCallProtocol
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.PhoneCall.phoneCallAccepted(Cons_phoneCallAccepted(flags: _1!, id: _2!, accessHash: _3!, date: _4!, adminId: _5!, participantId: _6!, gB: _7!, protocol: _8!))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallDiscarded(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Api.PhoneCallDiscardReason?
            if Int(_1!) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.PhoneCallDiscardReason
                }
            }
            var _4: Int32?
            if Int(_1!) & Int(1 << 1) != 0 {
                _4 = reader.readInt32()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 1) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PhoneCall.phoneCallDiscarded(Cons_phoneCallDiscarded(flags: _1!, id: _2!, reason: _3, duration: _4))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallEmpty(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int64?
            _1 = reader.readInt64()
            let _c1 = _1 != nil
            if _c1 {
                return Api.PhoneCall.phoneCallEmpty(Cons_phoneCallEmpty(id: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallRequested(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int64?
            _5 = reader.readInt64()
            var _6: Int64?
            _6 = reader.readInt64()
            var _7: Buffer?
            _7 = parseBytes(reader)
            var _8: Api.PhoneCallProtocol?
            if let signature = reader.readInt32() {
                _8 = Api.parse(reader, signature: signature) as? Api.PhoneCallProtocol
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.PhoneCall.phoneCallRequested(Cons_phoneCallRequested(flags: _1!, id: _2!, accessHash: _3!, date: _4!, adminId: _5!, participantId: _6!, gAHash: _7!, protocol: _8!))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallWaiting(_ reader: BufferReader) -> PhoneCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int64?
            _5 = reader.readInt64()
            var _6: Int64?
            _6 = reader.readInt64()
            var _7: Api.PhoneCallProtocol?
            if let signature = reader.readInt32() {
                _7 = Api.parse(reader, signature: signature) as? Api.PhoneCallProtocol
            }
            var _8: Int32?
            if Int(_1!) & Int(1 << 0) != 0 {
                _8 = reader.readInt32()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = (Int(_1!) & Int(1 << 0) == 0) || _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.PhoneCall.phoneCallWaiting(Cons_phoneCallWaiting(flags: _1!, id: _2!, accessHash: _3!, date: _4!, adminId: _5!, participantId: _6!, protocol: _7!, receiveDate: _8))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PhoneCallDiscardReason: TypeConstructorDescription {
        public class Cons_phoneCallDiscardReasonMigrateConferenceCall: TypeConstructorDescription {
            public var slug: String
            public init(slug: String) {
                self.slug = slug
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallDiscardReasonMigrateConferenceCall", [("slug", ConstructorParameterDescription(self.slug))])
            }
        }
        case phoneCallDiscardReasonBusy
        case phoneCallDiscardReasonDisconnect
        case phoneCallDiscardReasonHangup
        case phoneCallDiscardReasonMigrateConferenceCall(Cons_phoneCallDiscardReasonMigrateConferenceCall)
        case phoneCallDiscardReasonMissed

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .phoneCallDiscardReasonBusy:
                if boxed {
                    buffer.appendInt32(-84416311)
                }
                break
            case .phoneCallDiscardReasonDisconnect:
                if boxed {
                    buffer.appendInt32(-527056480)
                }
                break
            case .phoneCallDiscardReasonHangup:
                if boxed {
                    buffer.appendInt32(1471006352)
                }
                break
            case .phoneCallDiscardReasonMigrateConferenceCall(let _data):
                if boxed {
                    buffer.appendInt32(-1615072777)
                }
                serializeString(_data.slug, buffer: buffer, boxed: false)
                break
            case .phoneCallDiscardReasonMissed:
                if boxed {
                    buffer.appendInt32(-2048646399)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .phoneCallDiscardReasonBusy:
                return ("phoneCallDiscardReasonBusy", [])
            case .phoneCallDiscardReasonDisconnect:
                return ("phoneCallDiscardReasonDisconnect", [])
            case .phoneCallDiscardReasonHangup:
                return ("phoneCallDiscardReasonHangup", [])
            case .phoneCallDiscardReasonMigrateConferenceCall(let _data):
                return ("phoneCallDiscardReasonMigrateConferenceCall", [("slug", ConstructorParameterDescription(_data.slug))])
            case .phoneCallDiscardReasonMissed:
                return ("phoneCallDiscardReasonMissed", [])
            }
        }

        public static func parse_phoneCallDiscardReasonBusy(_ reader: BufferReader) -> PhoneCallDiscardReason? {
            return Api.PhoneCallDiscardReason.phoneCallDiscardReasonBusy
        }
        public static func parse_phoneCallDiscardReasonDisconnect(_ reader: BufferReader) -> PhoneCallDiscardReason? {
            return Api.PhoneCallDiscardReason.phoneCallDiscardReasonDisconnect
        }
        public static func parse_phoneCallDiscardReasonHangup(_ reader: BufferReader) -> PhoneCallDiscardReason? {
            return Api.PhoneCallDiscardReason.phoneCallDiscardReasonHangup
        }
        public static func parse_phoneCallDiscardReasonMigrateConferenceCall(_ reader: BufferReader) -> PhoneCallDiscardReason? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.PhoneCallDiscardReason.phoneCallDiscardReasonMigrateConferenceCall(Cons_phoneCallDiscardReasonMigrateConferenceCall(slug: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneCallDiscardReasonMissed(_ reader: BufferReader) -> PhoneCallDiscardReason? {
            return Api.PhoneCallDiscardReason.phoneCallDiscardReasonMissed
        }
    }
}
public extension Api {
    enum PhoneCallProtocol: TypeConstructorDescription {
        public class Cons_phoneCallProtocol: TypeConstructorDescription {
            public var flags: Int32
            public var minLayer: Int32
            public var maxLayer: Int32
            public var libraryVersions: [String]
            public init(flags: Int32, minLayer: Int32, maxLayer: Int32, libraryVersions: [String]) {
                self.flags = flags
                self.minLayer = minLayer
                self.maxLayer = maxLayer
                self.libraryVersions = libraryVersions
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneCallProtocol", [("flags", ConstructorParameterDescription(self.flags)), ("minLayer", ConstructorParameterDescription(self.minLayer)), ("maxLayer", ConstructorParameterDescription(self.maxLayer)), ("libraryVersions", ConstructorParameterDescription(self.libraryVersions))])
            }
        }
        case phoneCallProtocol(Cons_phoneCallProtocol)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .phoneCallProtocol(let _data):
                if boxed {
                    buffer.appendInt32(-58224696)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt32(_data.minLayer, buffer: buffer, boxed: false)
                serializeInt32(_data.maxLayer, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.libraryVersions.count))
                for item in _data.libraryVersions {
                    serializeString(item, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .phoneCallProtocol(let _data):
                return ("phoneCallProtocol", [("flags", ConstructorParameterDescription(_data.flags)), ("minLayer", ConstructorParameterDescription(_data.minLayer)), ("maxLayer", ConstructorParameterDescription(_data.maxLayer)), ("libraryVersions", ConstructorParameterDescription(_data.libraryVersions))])
            }
        }

        public static func parse_phoneCallProtocol(_ reader: BufferReader) -> PhoneCallProtocol? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: [String]?
            if let _ = reader.readInt32() {
                _4 = Api.parseVector(reader, elementSignature: -1255641564, elementType: String.self)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PhoneCallProtocol.phoneCallProtocol(Cons_phoneCallProtocol(flags: _1!, minLayer: _2!, maxLayer: _3!, libraryVersions: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PhoneConnection: TypeConstructorDescription {
        public class Cons_phoneConnection: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var ip: String
            public var ipv6: String
            public var port: Int32
            public var peerTag: Buffer
            public init(flags: Int32, id: Int64, ip: String, ipv6: String, port: Int32, peerTag: Buffer) {
                self.flags = flags
                self.id = id
                self.ip = ip
                self.ipv6 = ipv6
                self.port = port
                self.peerTag = peerTag
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneConnection", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("ip", ConstructorParameterDescription(self.ip)), ("ipv6", ConstructorParameterDescription(self.ipv6)), ("port", ConstructorParameterDescription(self.port)), ("peerTag", ConstructorParameterDescription(self.peerTag))])
            }
        }
        public class Cons_phoneConnectionWebrtc: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var ip: String
            public var ipv6: String
            public var port: Int32
            public var username: String
            public var password: String
            public init(flags: Int32, id: Int64, ip: String, ipv6: String, port: Int32, username: String, password: String) {
                self.flags = flags
                self.id = id
                self.ip = ip
                self.ipv6 = ipv6
                self.port = port
                self.username = username
                self.password = password
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("phoneConnectionWebrtc", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("ip", ConstructorParameterDescription(self.ip)), ("ipv6", ConstructorParameterDescription(self.ipv6)), ("port", ConstructorParameterDescription(self.port)), ("username", ConstructorParameterDescription(self.username)), ("password", ConstructorParameterDescription(self.password))])
            }
        }
        case phoneConnection(Cons_phoneConnection)
        case phoneConnectionWebrtc(Cons_phoneConnectionWebrtc)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .phoneConnection(let _data):
                if boxed {
                    buffer.appendInt32(-1665063993)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.ip, buffer: buffer, boxed: false)
                serializeString(_data.ipv6, buffer: buffer, boxed: false)
                serializeInt32(_data.port, buffer: buffer, boxed: false)
                serializeBytes(_data.peerTag, buffer: buffer, boxed: false)
                break
            case .phoneConnectionWebrtc(let _data):
                if boxed {
                    buffer.appendInt32(1667228533)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.ip, buffer: buffer, boxed: false)
                serializeString(_data.ipv6, buffer: buffer, boxed: false)
                serializeInt32(_data.port, buffer: buffer, boxed: false)
                serializeString(_data.username, buffer: buffer, boxed: false)
                serializeString(_data.password, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .phoneConnection(let _data):
                return ("phoneConnection", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("ip", ConstructorParameterDescription(_data.ip)), ("ipv6", ConstructorParameterDescription(_data.ipv6)), ("port", ConstructorParameterDescription(_data.port)), ("peerTag", ConstructorParameterDescription(_data.peerTag))])
            case .phoneConnectionWebrtc(let _data):
                return ("phoneConnectionWebrtc", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("ip", ConstructorParameterDescription(_data.ip)), ("ipv6", ConstructorParameterDescription(_data.ipv6)), ("port", ConstructorParameterDescription(_data.port)), ("username", ConstructorParameterDescription(_data.username)), ("password", ConstructorParameterDescription(_data.password))])
            }
        }

        public static func parse_phoneConnection(_ reader: BufferReader) -> PhoneConnection? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: Int32?
            _5 = reader.readInt32()
            var _6: Buffer?
            _6 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.PhoneConnection.phoneConnection(Cons_phoneConnection(flags: _1!, id: _2!, ip: _3!, ipv6: _4!, port: _5!, peerTag: _6!))
            }
            else {
                return nil
            }
        }
        public static func parse_phoneConnectionWebrtc(_ reader: BufferReader) -> PhoneConnection? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: Int32?
            _5 = reader.readInt32()
            var _6: String?
            _6 = parseString(reader)
            var _7: String?
            _7 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 {
                return Api.PhoneConnection.phoneConnectionWebrtc(Cons_phoneConnectionWebrtc(flags: _1!, id: _2!, ip: _3!, ipv6: _4!, port: _5!, username: _6!, password: _7!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum Photo: TypeConstructorDescription {
        public class Cons_photo: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var fileReference: Buffer
            public var date: Int32
            public var sizes: [Api.PhotoSize]
            public var videoSizes: [Api.VideoSize]?
            public var dcId: Int32
            public init(flags: Int32, id: Int64, accessHash: Int64, fileReference: Buffer, date: Int32, sizes: [Api.PhotoSize], videoSizes: [Api.VideoSize]?, dcId: Int32) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.fileReference = fileReference
                self.date = date
                self.sizes = sizes
                self.videoSizes = videoSizes
                self.dcId = dcId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photo", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("fileReference", ConstructorParameterDescription(self.fileReference)), ("date", ConstructorParameterDescription(self.date)), ("sizes", ConstructorParameterDescription(self.sizes)), ("videoSizes", ConstructorParameterDescription(self.videoSizes)), ("dcId", ConstructorParameterDescription(self.dcId))])
            }
        }
        public class Cons_photoEmpty: TypeConstructorDescription {
            public var id: Int64
            public init(id: Int64) {
                self.id = id
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoEmpty", [("id", ConstructorParameterDescription(self.id))])
            }
        }
        case photo(Cons_photo)
        case photoEmpty(Cons_photoEmpty)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .photo(let _data):
                if boxed {
                    buffer.appendInt32(-82216347)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeBytes(_data.fileReference, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.sizes.count))
                for item in _data.sizes {
                    item.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.videoSizes!.count))
                    for item in _data.videoSizes! {
                        item.serialize(buffer, true)
                    }
                }
                serializeInt32(_data.dcId, buffer: buffer, boxed: false)
                break
            case .photoEmpty(let _data):
                if boxed {
                    buffer.appendInt32(590459437)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .photo(let _data):
                return ("photo", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("fileReference", ConstructorParameterDescription(_data.fileReference)), ("date", ConstructorParameterDescription(_data.date)), ("sizes", ConstructorParameterDescription(_data.sizes)), ("videoSizes", ConstructorParameterDescription(_data.videoSizes)), ("dcId", ConstructorParameterDescription(_data.dcId))])
            case .photoEmpty(let _data):
                return ("photoEmpty", [("id", ConstructorParameterDescription(_data.id))])
            }
        }

        public static func parse_photo(_ reader: BufferReader) -> Photo? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Buffer?
            _4 = parseBytes(reader)
            var _5: Int32?
            _5 = reader.readInt32()
            var _6: [Api.PhotoSize]?
            if let _ = reader.readInt32() {
                _6 = Api.parseVector(reader, elementSignature: 0, elementType: Api.PhotoSize.self)
            }
            var _7: [Api.VideoSize]?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let _ = reader.readInt32() {
                    _7 = Api.parseVector(reader, elementSignature: 0, elementType: Api.VideoSize.self)
                }
            }
            var _8: Int32?
            _8 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = (Int(_1!) & Int(1 << 1) == 0) || _7 != nil
            let _c8 = _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.Photo.photo(Cons_photo(flags: _1!, id: _2!, accessHash: _3!, fileReference: _4!, date: _5!, sizes: _6!, videoSizes: _7, dcId: _8!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoEmpty(_ reader: BufferReader) -> Photo? {
            var _1: Int64?
            _1 = reader.readInt64()
            let _c1 = _1 != nil
            if _c1 {
                return Api.Photo.photoEmpty(Cons_photoEmpty(id: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PhotoSize: TypeConstructorDescription {
        public class Cons_photoCachedSize: TypeConstructorDescription {
            public var type: String
            public var w: Int32
            public var h: Int32
            public var bytes: Buffer
            public init(type: String, w: Int32, h: Int32, bytes: Buffer) {
                self.type = type
                self.w = w
                self.h = h
                self.bytes = bytes
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoCachedSize", [("type", ConstructorParameterDescription(self.type)), ("w", ConstructorParameterDescription(self.w)), ("h", ConstructorParameterDescription(self.h)), ("bytes", ConstructorParameterDescription(self.bytes))])
            }
        }
        public class Cons_photoPathSize: TypeConstructorDescription {
            public var type: String
            public var bytes: Buffer
            public init(type: String, bytes: Buffer) {
                self.type = type
                self.bytes = bytes
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoPathSize", [("type", ConstructorParameterDescription(self.type)), ("bytes", ConstructorParameterDescription(self.bytes))])
            }
        }
        public class Cons_photoSize: TypeConstructorDescription {
            public var type: String
            public var w: Int32
            public var h: Int32
            public var size: Int32
            public init(type: String, w: Int32, h: Int32, size: Int32) {
                self.type = type
                self.w = w
                self.h = h
                self.size = size
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoSize", [("type", ConstructorParameterDescription(self.type)), ("w", ConstructorParameterDescription(self.w)), ("h", ConstructorParameterDescription(self.h)), ("size", ConstructorParameterDescription(self.size))])
            }
        }
        public class Cons_photoSizeEmpty: TypeConstructorDescription {
            public var type: String
            public init(type: String) {
                self.type = type
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoSizeEmpty", [("type", ConstructorParameterDescription(self.type))])
            }
        }
        public class Cons_photoSizeProgressive: TypeConstructorDescription {
            public var type: String
            public var w: Int32
            public var h: Int32
            public var sizes: [Int32]
            public init(type: String, w: Int32, h: Int32, sizes: [Int32]) {
                self.type = type
                self.w = w
                self.h = h
                self.sizes = sizes
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoSizeProgressive", [("type", ConstructorParameterDescription(self.type)), ("w", ConstructorParameterDescription(self.w)), ("h", ConstructorParameterDescription(self.h)), ("sizes", ConstructorParameterDescription(self.sizes))])
            }
        }
        public class Cons_photoStrippedSize: TypeConstructorDescription {
            public var type: String
            public var bytes: Buffer
            public init(type: String, bytes: Buffer) {
                self.type = type
                self.bytes = bytes
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("photoStrippedSize", [("type", ConstructorParameterDescription(self.type)), ("bytes", ConstructorParameterDescription(self.bytes))])
            }
        }
        case photoCachedSize(Cons_photoCachedSize)
        case photoPathSize(Cons_photoPathSize)
        case photoSize(Cons_photoSize)
        case photoSizeEmpty(Cons_photoSizeEmpty)
        case photoSizeProgressive(Cons_photoSizeProgressive)
        case photoStrippedSize(Cons_photoStrippedSize)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .photoCachedSize(let _data):
                if boxed {
                    buffer.appendInt32(35527382)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeInt32(_data.w, buffer: buffer, boxed: false)
                serializeInt32(_data.h, buffer: buffer, boxed: false)
                serializeBytes(_data.bytes, buffer: buffer, boxed: false)
                break
            case .photoPathSize(let _data):
                if boxed {
                    buffer.appendInt32(-668906175)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeBytes(_data.bytes, buffer: buffer, boxed: false)
                break
            case .photoSize(let _data):
                if boxed {
                    buffer.appendInt32(1976012384)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeInt32(_data.w, buffer: buffer, boxed: false)
                serializeInt32(_data.h, buffer: buffer, boxed: false)
                serializeInt32(_data.size, buffer: buffer, boxed: false)
                break
            case .photoSizeEmpty(let _data):
                if boxed {
                    buffer.appendInt32(236446268)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                break
            case .photoSizeProgressive(let _data):
                if boxed {
                    buffer.appendInt32(-96535659)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeInt32(_data.w, buffer: buffer, boxed: false)
                serializeInt32(_data.h, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.sizes.count))
                for item in _data.sizes {
                    serializeInt32(item, buffer: buffer, boxed: false)
                }
                break
            case .photoStrippedSize(let _data):
                if boxed {
                    buffer.appendInt32(-525288402)
                }
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeBytes(_data.bytes, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .photoCachedSize(let _data):
                return ("photoCachedSize", [("type", ConstructorParameterDescription(_data.type)), ("w", ConstructorParameterDescription(_data.w)), ("h", ConstructorParameterDescription(_data.h)), ("bytes", ConstructorParameterDescription(_data.bytes))])
            case .photoPathSize(let _data):
                return ("photoPathSize", [("type", ConstructorParameterDescription(_data.type)), ("bytes", ConstructorParameterDescription(_data.bytes))])
            case .photoSize(let _data):
                return ("photoSize", [("type", ConstructorParameterDescription(_data.type)), ("w", ConstructorParameterDescription(_data.w)), ("h", ConstructorParameterDescription(_data.h)), ("size", ConstructorParameterDescription(_data.size))])
            case .photoSizeEmpty(let _data):
                return ("photoSizeEmpty", [("type", ConstructorParameterDescription(_data.type))])
            case .photoSizeProgressive(let _data):
                return ("photoSizeProgressive", [("type", ConstructorParameterDescription(_data.type)), ("w", ConstructorParameterDescription(_data.w)), ("h", ConstructorParameterDescription(_data.h)), ("sizes", ConstructorParameterDescription(_data.sizes))])
            case .photoStrippedSize(let _data):
                return ("photoStrippedSize", [("type", ConstructorParameterDescription(_data.type)), ("bytes", ConstructorParameterDescription(_data.bytes))])
            }
        }

        public static func parse_photoCachedSize(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Buffer?
            _4 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PhotoSize.photoCachedSize(Cons_photoCachedSize(type: _1!, w: _2!, h: _3!, bytes: _4!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoPathSize(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Buffer?
            _2 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.PhotoSize.photoPathSize(Cons_photoPathSize(type: _1!, bytes: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoSize(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PhotoSize.photoSize(Cons_photoSize(type: _1!, w: _2!, h: _3!, size: _4!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoSizeEmpty(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.PhotoSize.photoSizeEmpty(Cons_photoSizeEmpty(type: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoSizeProgressive(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: [Int32]?
            if let _ = reader.readInt32() {
                _4 = Api.parseVector(reader, elementSignature: -1471112230, elementType: Int32.self)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PhotoSize.photoSizeProgressive(Cons_photoSizeProgressive(type: _1!, w: _2!, h: _3!, sizes: _4!))
            }
            else {
                return nil
            }
        }
        public static func parse_photoStrippedSize(_ reader: BufferReader) -> PhotoSize? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Buffer?
            _2 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.PhotoSize.photoStrippedSize(Cons_photoStrippedSize(type: _1!, bytes: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum Poll: TypeConstructorDescription {
        public class Cons_poll: TypeConstructorDescription {
            public var id: Int64
            public var flags: Int32
            public var question: Api.TextWithEntities
            public var answers: [Api.PollAnswer]
            public var closePeriod: Int32?
            public var closeDate: Int32?
            public var countriesIso2: [String]?
            public var hash: Int64
            public init(id: Int64, flags: Int32, question: Api.TextWithEntities, answers: [Api.PollAnswer], closePeriod: Int32?, closeDate: Int32?, countriesIso2: [String]?, hash: Int64) {
                self.id = id
                self.flags = flags
                self.question = question
                self.answers = answers
                self.closePeriod = closePeriod
                self.closeDate = closeDate
                self.countriesIso2 = countriesIso2
                self.hash = hash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("poll", [("id", ConstructorParameterDescription(self.id)), ("flags", ConstructorParameterDescription(self.flags)), ("question", ConstructorParameterDescription(self.question)), ("answers", ConstructorParameterDescription(self.answers)), ("closePeriod", ConstructorParameterDescription(self.closePeriod)), ("closeDate", ConstructorParameterDescription(self.closeDate)), ("countriesIso2", ConstructorParameterDescription(self.countriesIso2)), ("hash", ConstructorParameterDescription(self.hash))])
            }
        }
        case poll(Cons_poll)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .poll(let _data):
                if boxed {
                    buffer.appendInt32(-1771164225)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.question.serialize(buffer, true)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.answers.count))
                for item in _data.answers {
                    item.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    serializeInt32(_data.closePeriod!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 5) != 0 {
                    serializeInt32(_data.closeDate!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 12) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.countriesIso2!.count))
                    for item in _data.countriesIso2! {
                        serializeString(item, buffer: buffer, boxed: false)
                    }
                }
                serializeInt64(_data.hash, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .poll(let _data):
                return ("poll", [("id", ConstructorParameterDescription(_data.id)), ("flags", ConstructorParameterDescription(_data.flags)), ("question", ConstructorParameterDescription(_data.question)), ("answers", ConstructorParameterDescription(_data.answers)), ("closePeriod", ConstructorParameterDescription(_data.closePeriod)), ("closeDate", ConstructorParameterDescription(_data.closeDate)), ("countriesIso2", ConstructorParameterDescription(_data.countriesIso2)), ("hash", ConstructorParameterDescription(_data.hash))])
            }
        }

        public static func parse_poll(_ reader: BufferReader) -> Poll? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Api.TextWithEntities?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.TextWithEntities
            }
            var _4: [Api.PollAnswer]?
            if let _ = reader.readInt32() {
                _4 = Api.parseVector(reader, elementSignature: 0, elementType: Api.PollAnswer.self)
            }
            var _5: Int32?
            if Int(_2!) & Int(1 << 4) != 0 {
                _5 = reader.readInt32()
            }
            var _6: Int32?
            if Int(_2!) & Int(1 << 5) != 0 {
                _6 = reader.readInt32()
            }
            var _7: [String]?
            if Int(_2!) & Int(1 << 12) != 0 {
                if let _ = reader.readInt32() {
                    _7 = Api.parseVector(reader, elementSignature: -1255641564, elementType: String.self)
                }
            }
            var _8: Int64?
            _8 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = (Int(_2!) & Int(1 << 4) == 0) || _5 != nil
            let _c6 = (Int(_2!) & Int(1 << 5) == 0) || _6 != nil
            let _c7 = (Int(_2!) & Int(1 << 12) == 0) || _7 != nil
            let _c8 = _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.Poll.poll(Cons_poll(id: _1!, flags: _2!, question: _3!, answers: _4!, closePeriod: _5, closeDate: _6, countriesIso2: _7, hash: _8!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum PollAnswer: TypeConstructorDescription {
        public class Cons_inputPollAnswer: TypeConstructorDescription {
            public var flags: Int32
            public var text: Api.TextWithEntities
            public var media: Api.InputMedia?
            public init(flags: Int32, text: Api.TextWithEntities, media: Api.InputMedia?) {
                self.flags = flags
                self.text = text
                self.media = media
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputPollAnswer", [("flags", ConstructorParameterDescription(self.flags)), ("text", ConstructorParameterDescription(self.text)), ("media", ConstructorParameterDescription(self.media))])
            }
        }
        public class Cons_pollAnswer: TypeConstructorDescription {
            public var flags: Int32
            public var text: Api.TextWithEntities
            public var option: Buffer
            public var media: Api.MessageMedia?
            public var addedBy: Api.Peer?
            public var date: Int32?
            public init(flags: Int32, text: Api.TextWithEntities, option: Buffer, media: Api.MessageMedia?, addedBy: Api.Peer?, date: Int32?) {
                self.flags = flags
                self.text = text
                self.option = option
                self.media = media
                self.addedBy = addedBy
                self.date = date
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("pollAnswer", [("flags", ConstructorParameterDescription(self.flags)), ("text", ConstructorParameterDescription(self.text)), ("option", ConstructorParameterDescription(self.option)), ("media", ConstructorParameterDescription(self.media)), ("addedBy", ConstructorParameterDescription(self.addedBy)), ("date", ConstructorParameterDescription(self.date))])
            }
        }
        case inputPollAnswer(Cons_inputPollAnswer)
        case pollAnswer(Cons_pollAnswer)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputPollAnswer(let _data):
                if boxed {
                    buffer.appendInt32(429911446)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.text.serialize(buffer, true)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.media!.serialize(buffer, true)
                }
                break
            case .pollAnswer(let _data):
                if boxed {
                    buffer.appendInt32(1266514026)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.text.serialize(buffer, true)
                serializeBytes(_data.option, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.media!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.addedBy!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeInt32(_data.date!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputPollAnswer(let _data):
                return ("inputPollAnswer", [("flags", ConstructorParameterDescription(_data.flags)), ("text", ConstructorParameterDescription(_data.text)), ("media", ConstructorParameterDescription(_data.media))])
            case .pollAnswer(let _data):
                return ("pollAnswer", [("flags", ConstructorParameterDescription(_data.flags)), ("text", ConstructorParameterDescription(_data.text)), ("option", ConstructorParameterDescription(_data.option)), ("media", ConstructorParameterDescription(_data.media)), ("addedBy", ConstructorParameterDescription(_data.addedBy)), ("date", ConstructorParameterDescription(_data.date))])
            }
        }

        public static func parse_inputPollAnswer(_ reader: BufferReader) -> PollAnswer? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.TextWithEntities?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.TextWithEntities
            }
            var _3: Api.InputMedia?
            if Int(_1!) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.InputMedia
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 0) == 0) || _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.PollAnswer.inputPollAnswer(Cons_inputPollAnswer(flags: _1!, text: _2!, media: _3))
            }
            else {
                return nil
            }
        }
        public static func parse_pollAnswer(_ reader: BufferReader) -> PollAnswer? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.TextWithEntities?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.TextWithEntities
            }
            var _3: Buffer?
            _3 = parseBytes(reader)
            var _4: Api.MessageMedia?
            if Int(_1!) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.MessageMedia
                }
            }
            var _5: Api.Peer?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _5 = Api.parse(reader, signature: signature) as? Api.Peer
                }
            }
            var _6: Int32?
            if Int(_1!) & Int(1 << 1) != 0 {
                _6 = reader.readInt32()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 0) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 1) == 0) || _5 != nil
            let _c6 = (Int(_1!) & Int(1 << 1) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.PollAnswer.pollAnswer(Cons_pollAnswer(flags: _1!, text: _2!, option: _3!, media: _4, addedBy: _5, date: _6))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PollAnswerVoters: TypeConstructorDescription {
        public class Cons_pollAnswerVoters: TypeConstructorDescription {
            public var flags: Int32
            public var option: Buffer
            public var voters: Int32?
            public var recentVoters: [Api.Peer]?
            public init(flags: Int32, option: Buffer, voters: Int32?, recentVoters: [Api.Peer]?) {
                self.flags = flags
                self.option = option
                self.voters = voters
                self.recentVoters = recentVoters
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("pollAnswerVoters", [("flags", ConstructorParameterDescription(self.flags)), ("option", ConstructorParameterDescription(self.option)), ("voters", ConstructorParameterDescription(self.voters)), ("recentVoters", ConstructorParameterDescription(self.recentVoters))])
            }
        }
        case pollAnswerVoters(Cons_pollAnswerVoters)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .pollAnswerVoters(let _data):
                if boxed {
                    buffer.appendInt32(910500618)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeBytes(_data.option, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeInt32(_data.voters!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.recentVoters!.count))
                    for item in _data.recentVoters! {
                        item.serialize(buffer, true)
                    }
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .pollAnswerVoters(let _data):
                return ("pollAnswerVoters", [("flags", ConstructorParameterDescription(_data.flags)), ("option", ConstructorParameterDescription(_data.option)), ("voters", ConstructorParameterDescription(_data.voters)), ("recentVoters", ConstructorParameterDescription(_data.recentVoters))])
            }
        }

        public static func parse_pollAnswerVoters(_ reader: BufferReader) -> PollAnswerVoters? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Buffer?
            _2 = parseBytes(reader)
            var _3: Int32?
            if Int(_1!) & Int(1 << 2) != 0 {
                _3 = reader.readInt32()
            }
            var _4: [Api.Peer]?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let _ = reader.readInt32() {
                    _4 = Api.parseVector(reader, elementSignature: 0, elementType: Api.Peer.self)
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 2) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 2) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PollAnswerVoters.pollAnswerVoters(Cons_pollAnswerVoters(flags: _1!, option: _2!, voters: _3, recentVoters: _4))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum PollResults: TypeConstructorDescription {
        public class Cons_pollResults: TypeConstructorDescription {
            public var flags: Int32
            public var results: [Api.PollAnswerVoters]?
            public var totalVoters: Int32?
            public var recentVoters: [Api.Peer]?
            public var solution: String?
            public var solutionEntities: [Api.MessageEntity]?
            public var solutionMedia: Api.MessageMedia?
            public init(flags: Int32, results: [Api.PollAnswerVoters]?, totalVoters: Int32?, recentVoters: [Api.Peer]?, solution: String?, solutionEntities: [Api.MessageEntity]?, solutionMedia: Api.MessageMedia?) {
                self.flags = flags
                self.results = results
                self.totalVoters = totalVoters
                self.recentVoters = recentVoters
                self.solution = solution
                self.solutionEntities = solutionEntities
                self.solutionMedia = solutionMedia
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("pollResults", [("flags", ConstructorParameterDescription(self.flags)), ("results", ConstructorParameterDescription(self.results)), ("totalVoters", ConstructorParameterDescription(self.totalVoters)), ("recentVoters", ConstructorParameterDescription(self.recentVoters)), ("solution", ConstructorParameterDescription(self.solution)), ("solutionEntities", ConstructorParameterDescription(self.solutionEntities)), ("solutionMedia", ConstructorParameterDescription(self.solutionMedia))])
            }
        }
        case pollResults(Cons_pollResults)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .pollResults(let _data):
                if boxed {
                    buffer.appendInt32(-1166298786)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.results!.count))
                    for item in _data.results! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeInt32(_data.totalVoters!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.recentVoters!.count))
                    for item in _data.recentVoters! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    serializeString(_data.solution!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.solutionEntities!.count))
                    for item in _data.solutionEntities! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 5) != 0 {
                    _data.solutionMedia!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .pollResults(let _data):
                return ("pollResults", [("flags", ConstructorParameterDescription(_data.flags)), ("results", ConstructorParameterDescription(_data.results)), ("totalVoters", ConstructorParameterDescription(_data.totalVoters)), ("recentVoters", ConstructorParameterDescription(_data.recentVoters)), ("solution", ConstructorParameterDescription(_data.solution)), ("solutionEntities", ConstructorParameterDescription(_data.solutionEntities)), ("solutionMedia", ConstructorParameterDescription(_data.solutionMedia))])
            }
        }

        public static func parse_pollResults(_ reader: BufferReader) -> PollResults? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: [Api.PollAnswerVoters]?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let _ = reader.readInt32() {
                    _2 = Api.parseVector(reader, elementSignature: 0, elementType: Api.PollAnswerVoters.self)
                }
            }
            var _3: Int32?
            if Int(_1!) & Int(1 << 2) != 0 {
                _3 = reader.readInt32()
            }
            var _4: [Api.Peer]?
            if Int(_1!) & Int(1 << 3) != 0 {
                if let _ = reader.readInt32() {
                    _4 = Api.parseVector(reader, elementSignature: 0, elementType: Api.Peer.self)
                }
            }
            var _5: String?
            if Int(_1!) & Int(1 << 4) != 0 {
                _5 = parseString(reader)
            }
            var _6: [Api.MessageEntity]?
            if Int(_1!) & Int(1 << 4) != 0 {
                if let _ = reader.readInt32() {
                    _6 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageEntity.self)
                }
            }
            var _7: Api.MessageMedia?
            if Int(_1!) & Int(1 << 5) != 0 {
                if let signature = reader.readInt32() {
                    _7 = Api.parse(reader, signature: signature) as? Api.MessageMedia
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 1) == 0) || _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 2) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 3) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 4) == 0) || _5 != nil
            let _c6 = (Int(_1!) & Int(1 << 4) == 0) || _6 != nil
            let _c7 = (Int(_1!) & Int(1 << 5) == 0) || _7 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 {
                return Api.PollResults.pollResults(Cons_pollResults(flags: _1!, results: _2, totalVoters: _3, recentVoters: _4, solution: _5, solutionEntities: _6, solutionMedia: _7))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PopularContact: TypeConstructorDescription {
        public class Cons_popularContact: TypeConstructorDescription {
            public var clientId: Int64
            public var importers: Int32
            public init(clientId: Int64, importers: Int32) {
                self.clientId = clientId
                self.importers = importers
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("popularContact", [("clientId", ConstructorParameterDescription(self.clientId)), ("importers", ConstructorParameterDescription(self.importers))])
            }
        }
        case popularContact(Cons_popularContact)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .popularContact(let _data):
                if boxed {
                    buffer.appendInt32(1558266229)
                }
                serializeInt64(_data.clientId, buffer: buffer, boxed: false)
                serializeInt32(_data.importers, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .popularContact(let _data):
                return ("popularContact", [("clientId", ConstructorParameterDescription(_data.clientId)), ("importers", ConstructorParameterDescription(_data.importers))])
            }
        }

        public static func parse_popularContact(_ reader: BufferReader) -> PopularContact? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int32?
            _2 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.PopularContact.popularContact(Cons_popularContact(clientId: _1!, importers: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PostAddress: TypeConstructorDescription {
        public class Cons_postAddress: TypeConstructorDescription {
            public var streetLine1: String
            public var streetLine2: String
            public var city: String
            public var state: String
            public var countryIso2: String
            public var postCode: String
            public init(streetLine1: String, streetLine2: String, city: String, state: String, countryIso2: String, postCode: String) {
                self.streetLine1 = streetLine1
                self.streetLine2 = streetLine2
                self.city = city
                self.state = state
                self.countryIso2 = countryIso2
                self.postCode = postCode
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("postAddress", [("streetLine1", ConstructorParameterDescription(self.streetLine1)), ("streetLine2", ConstructorParameterDescription(self.streetLine2)), ("city", ConstructorParameterDescription(self.city)), ("state", ConstructorParameterDescription(self.state)), ("countryIso2", ConstructorParameterDescription(self.countryIso2)), ("postCode", ConstructorParameterDescription(self.postCode))])
            }
        }
        case postAddress(Cons_postAddress)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .postAddress(let _data):
                if boxed {
                    buffer.appendInt32(512535275)
                }
                serializeString(_data.streetLine1, buffer: buffer, boxed: false)
                serializeString(_data.streetLine2, buffer: buffer, boxed: false)
                serializeString(_data.city, buffer: buffer, boxed: false)
                serializeString(_data.state, buffer: buffer, boxed: false)
                serializeString(_data.countryIso2, buffer: buffer, boxed: false)
                serializeString(_data.postCode, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .postAddress(let _data):
                return ("postAddress", [("streetLine1", ConstructorParameterDescription(_data.streetLine1)), ("streetLine2", ConstructorParameterDescription(_data.streetLine2)), ("city", ConstructorParameterDescription(_data.city)), ("state", ConstructorParameterDescription(_data.state)), ("countryIso2", ConstructorParameterDescription(_data.countryIso2)), ("postCode", ConstructorParameterDescription(_data.postCode))])
            }
        }

        public static func parse_postAddress(_ reader: BufferReader) -> PostAddress? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: String?
            _5 = parseString(reader)
            var _6: String?
            _6 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.PostAddress.postAddress(Cons_postAddress(streetLine1: _1!, streetLine2: _2!, city: _3!, state: _4!, countryIso2: _5!, postCode: _6!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PostInteractionCounters: TypeConstructorDescription {
        public class Cons_postInteractionCountersMessage: TypeConstructorDescription {
            public var msgId: Int32
            public var views: Int32
            public var forwards: Int32
            public var reactions: Int32
            public init(msgId: Int32, views: Int32, forwards: Int32, reactions: Int32) {
                self.msgId = msgId
                self.views = views
                self.forwards = forwards
                self.reactions = reactions
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("postInteractionCountersMessage", [("msgId", ConstructorParameterDescription(self.msgId)), ("views", ConstructorParameterDescription(self.views)), ("forwards", ConstructorParameterDescription(self.forwards)), ("reactions", ConstructorParameterDescription(self.reactions))])
            }
        }
        public class Cons_postInteractionCountersStory: TypeConstructorDescription {
            public var storyId: Int32
            public var views: Int32
            public var forwards: Int32
            public var reactions: Int32
            public init(storyId: Int32, views: Int32, forwards: Int32, reactions: Int32) {
                self.storyId = storyId
                self.views = views
                self.forwards = forwards
                self.reactions = reactions
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("postInteractionCountersStory", [("storyId", ConstructorParameterDescription(self.storyId)), ("views", ConstructorParameterDescription(self.views)), ("forwards", ConstructorParameterDescription(self.forwards)), ("reactions", ConstructorParameterDescription(self.reactions))])
            }
        }
        case postInteractionCountersMessage(Cons_postInteractionCountersMessage)
        case postInteractionCountersStory(Cons_postInteractionCountersStory)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .postInteractionCountersMessage(let _data):
                if boxed {
                    buffer.appendInt32(-419066241)
                }
                serializeInt32(_data.msgId, buffer: buffer, boxed: false)
                serializeInt32(_data.views, buffer: buffer, boxed: false)
                serializeInt32(_data.forwards, buffer: buffer, boxed: false)
                serializeInt32(_data.reactions, buffer: buffer, boxed: false)
                break
            case .postInteractionCountersStory(let _data):
                if boxed {
                    buffer.appendInt32(-1974989273)
                }
                serializeInt32(_data.storyId, buffer: buffer, boxed: false)
                serializeInt32(_data.views, buffer: buffer, boxed: false)
                serializeInt32(_data.forwards, buffer: buffer, boxed: false)
                serializeInt32(_data.reactions, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .postInteractionCountersMessage(let _data):
                return ("postInteractionCountersMessage", [("msgId", ConstructorParameterDescription(_data.msgId)), ("views", ConstructorParameterDescription(_data.views)), ("forwards", ConstructorParameterDescription(_data.forwards)), ("reactions", ConstructorParameterDescription(_data.reactions))])
            case .postInteractionCountersStory(let _data):
                return ("postInteractionCountersStory", [("storyId", ConstructorParameterDescription(_data.storyId)), ("views", ConstructorParameterDescription(_data.views)), ("forwards", ConstructorParameterDescription(_data.forwards)), ("reactions", ConstructorParameterDescription(_data.reactions))])
            }
        }

        public static func parse_postInteractionCountersMessage(_ reader: BufferReader) -> PostInteractionCounters? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PostInteractionCounters.postInteractionCountersMessage(Cons_postInteractionCountersMessage(msgId: _1!, views: _2!, forwards: _3!, reactions: _4!))
            }
            else {
                return nil
            }
        }
        public static func parse_postInteractionCountersStory(_ reader: BufferReader) -> PostInteractionCounters? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PostInteractionCounters.postInteractionCountersStory(Cons_postInteractionCountersStory(storyId: _1!, views: _2!, forwards: _3!, reactions: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PremiumGiftCodeOption: TypeConstructorDescription {
        public class Cons_premiumGiftCodeOption: TypeConstructorDescription {
            public var flags: Int32
            public var users: Int32
            public var months: Int32
            public var storeProduct: String?
            public var storeQuantity: Int32?
            public var currency: String
            public var amount: Int64
            public init(flags: Int32, users: Int32, months: Int32, storeProduct: String?, storeQuantity: Int32?, currency: String, amount: Int64) {
                self.flags = flags
                self.users = users
                self.months = months
                self.storeProduct = storeProduct
                self.storeQuantity = storeQuantity
                self.currency = currency
                self.amount = amount
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("premiumGiftCodeOption", [("flags", ConstructorParameterDescription(self.flags)), ("users", ConstructorParameterDescription(self.users)), ("months", ConstructorParameterDescription(self.months)), ("storeProduct", ConstructorParameterDescription(self.storeProduct)), ("storeQuantity", ConstructorParameterDescription(self.storeQuantity)), ("currency", ConstructorParameterDescription(self.currency)), ("amount", ConstructorParameterDescription(self.amount))])
            }
        }
        case premiumGiftCodeOption(Cons_premiumGiftCodeOption)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .premiumGiftCodeOption(let _data):
                if boxed {
                    buffer.appendInt32(629052971)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt32(_data.users, buffer: buffer, boxed: false)
                serializeInt32(_data.months, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.storeProduct!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeInt32(_data.storeQuantity!, buffer: buffer, boxed: false)
                }
                serializeString(_data.currency, buffer: buffer, boxed: false)
                serializeInt64(_data.amount, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .premiumGiftCodeOption(let _data):
                return ("premiumGiftCodeOption", [("flags", ConstructorParameterDescription(_data.flags)), ("users", ConstructorParameterDescription(_data.users)), ("months", ConstructorParameterDescription(_data.months)), ("storeProduct", ConstructorParameterDescription(_data.storeProduct)), ("storeQuantity", ConstructorParameterDescription(_data.storeQuantity)), ("currency", ConstructorParameterDescription(_data.currency)), ("amount", ConstructorParameterDescription(_data.amount))])
            }
        }

        public static func parse_premiumGiftCodeOption(_ reader: BufferReader) -> PremiumGiftCodeOption? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _4 = parseString(reader)
            }
            var _5: Int32?
            if Int(_1!) & Int(1 << 1) != 0 {
                _5 = reader.readInt32()
            }
            var _6: String?
            _6 = parseString(reader)
            var _7: Int64?
            _7 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 0) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 1) == 0) || _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 {
                return Api.PremiumGiftCodeOption.premiumGiftCodeOption(Cons_premiumGiftCodeOption(flags: _1!, users: _2!, months: _3!, storeProduct: _4, storeQuantity: _5, currency: _6!, amount: _7!))
            }
            else {
                return nil
            }
        }
    }
}
