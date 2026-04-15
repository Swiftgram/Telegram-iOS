public extension Api {
    enum ReportResult: TypeConstructorDescription {
        public class Cons_reportResultAddComment: TypeConstructorDescription {
            public var flags: Int32
            public var option: Buffer
            public init(flags: Int32, option: Buffer) {
                self.flags = flags
                self.option = option
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("reportResultAddComment", [("flags", ConstructorParameterDescription(self.flags)), ("option", ConstructorParameterDescription(self.option))])
            }
        }
        public class Cons_reportResultChooseOption: TypeConstructorDescription {
            public var title: String
            public var options: [Api.MessageReportOption]
            public init(title: String, options: [Api.MessageReportOption]) {
                self.title = title
                self.options = options
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("reportResultChooseOption", [("title", ConstructorParameterDescription(self.title)), ("options", ConstructorParameterDescription(self.options))])
            }
        }
        case reportResultAddComment(Cons_reportResultAddComment)
        case reportResultChooseOption(Cons_reportResultChooseOption)
        case reportResultReported

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .reportResultAddComment(let _data):
                if boxed {
                    buffer.appendInt32(1862904881)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeBytes(_data.option, buffer: buffer, boxed: false)
                break
            case .reportResultChooseOption(let _data):
                if boxed {
                    buffer.appendInt32(-253435722)
                }
                serializeString(_data.title, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.options.count))
                for item in _data.options {
                    item.serialize(buffer, true)
                }
                break
            case .reportResultReported:
                if boxed {
                    buffer.appendInt32(-1917633461)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .reportResultAddComment(let _data):
                return ("reportResultAddComment", [("flags", ConstructorParameterDescription(_data.flags)), ("option", ConstructorParameterDescription(_data.option))])
            case .reportResultChooseOption(let _data):
                return ("reportResultChooseOption", [("title", ConstructorParameterDescription(_data.title)), ("options", ConstructorParameterDescription(_data.options))])
            case .reportResultReported:
                return ("reportResultReported", [])
            }
        }

        public static func parse_reportResultAddComment(_ reader: BufferReader) -> ReportResult? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Buffer?
            _2 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.ReportResult.reportResultAddComment(Cons_reportResultAddComment(flags: _1!, option: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_reportResultChooseOption(_ reader: BufferReader) -> ReportResult? {
            var _1: String?
            _1 = parseString(reader)
            var _2: [Api.MessageReportOption]?
            if let _ = reader.readInt32() {
                _2 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageReportOption.self)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.ReportResult.reportResultChooseOption(Cons_reportResultChooseOption(title: _1!, options: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_reportResultReported(_ reader: BufferReader) -> ReportResult? {
            return Api.ReportResult.reportResultReported
        }
    }
}
public extension Api {
    enum RequestPeerType: TypeConstructorDescription {
        public class Cons_requestPeerTypeBroadcast: TypeConstructorDescription {
            public var flags: Int32
            public var hasUsername: Api.Bool?
            public var userAdminRights: Api.ChatAdminRights?
            public var botAdminRights: Api.ChatAdminRights?
            public init(flags: Int32, hasUsername: Api.Bool?, userAdminRights: Api.ChatAdminRights?, botAdminRights: Api.ChatAdminRights?) {
                self.flags = flags
                self.hasUsername = hasUsername
                self.userAdminRights = userAdminRights
                self.botAdminRights = botAdminRights
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestPeerTypeBroadcast", [("flags", ConstructorParameterDescription(self.flags)), ("hasUsername", ConstructorParameterDescription(self.hasUsername)), ("userAdminRights", ConstructorParameterDescription(self.userAdminRights)), ("botAdminRights", ConstructorParameterDescription(self.botAdminRights))])
            }
        }
        public class Cons_requestPeerTypeChat: TypeConstructorDescription {
            public var flags: Int32
            public var hasUsername: Api.Bool?
            public var forum: Api.Bool?
            public var userAdminRights: Api.ChatAdminRights?
            public var botAdminRights: Api.ChatAdminRights?
            public init(flags: Int32, hasUsername: Api.Bool?, forum: Api.Bool?, userAdminRights: Api.ChatAdminRights?, botAdminRights: Api.ChatAdminRights?) {
                self.flags = flags
                self.hasUsername = hasUsername
                self.forum = forum
                self.userAdminRights = userAdminRights
                self.botAdminRights = botAdminRights
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestPeerTypeChat", [("flags", ConstructorParameterDescription(self.flags)), ("hasUsername", ConstructorParameterDescription(self.hasUsername)), ("forum", ConstructorParameterDescription(self.forum)), ("userAdminRights", ConstructorParameterDescription(self.userAdminRights)), ("botAdminRights", ConstructorParameterDescription(self.botAdminRights))])
            }
        }
        public class Cons_requestPeerTypeCreateBot: TypeConstructorDescription {
            public var flags: Int32
            public var suggestedName: String?
            public var suggestedUsername: String?
            public init(flags: Int32, suggestedName: String?, suggestedUsername: String?) {
                self.flags = flags
                self.suggestedName = suggestedName
                self.suggestedUsername = suggestedUsername
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestPeerTypeCreateBot", [("flags", ConstructorParameterDescription(self.flags)), ("suggestedName", ConstructorParameterDescription(self.suggestedName)), ("suggestedUsername", ConstructorParameterDescription(self.suggestedUsername))])
            }
        }
        public class Cons_requestPeerTypeUser: TypeConstructorDescription {
            public var flags: Int32
            public var bot: Api.Bool?
            public var premium: Api.Bool?
            public init(flags: Int32, bot: Api.Bool?, premium: Api.Bool?) {
                self.flags = flags
                self.bot = bot
                self.premium = premium
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestPeerTypeUser", [("flags", ConstructorParameterDescription(self.flags)), ("bot", ConstructorParameterDescription(self.bot)), ("premium", ConstructorParameterDescription(self.premium))])
            }
        }
        case requestPeerTypeBroadcast(Cons_requestPeerTypeBroadcast)
        case requestPeerTypeChat(Cons_requestPeerTypeChat)
        case requestPeerTypeCreateBot(Cons_requestPeerTypeCreateBot)
        case requestPeerTypeUser(Cons_requestPeerTypeUser)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .requestPeerTypeBroadcast(let _data):
                if boxed {
                    buffer.appendInt32(865857388)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    _data.hasUsername!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.userAdminRights!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.botAdminRights!.serialize(buffer, true)
                }
                break
            case .requestPeerTypeChat(let _data):
                if boxed {
                    buffer.appendInt32(-906990053)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    _data.hasUsername!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    _data.forum!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.userAdminRights!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.botAdminRights!.serialize(buffer, true)
                }
                break
            case .requestPeerTypeCreateBot(let _data):
                if boxed {
                    buffer.appendInt32(1048699000)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.suggestedName!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeString(_data.suggestedUsername!, buffer: buffer, boxed: false)
                }
                break
            case .requestPeerTypeUser(let _data):
                if boxed {
                    buffer.appendInt32(1597737472)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.bot!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.premium!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .requestPeerTypeBroadcast(let _data):
                return ("requestPeerTypeBroadcast", [("flags", ConstructorParameterDescription(_data.flags)), ("hasUsername", ConstructorParameterDescription(_data.hasUsername)), ("userAdminRights", ConstructorParameterDescription(_data.userAdminRights)), ("botAdminRights", ConstructorParameterDescription(_data.botAdminRights))])
            case .requestPeerTypeChat(let _data):
                return ("requestPeerTypeChat", [("flags", ConstructorParameterDescription(_data.flags)), ("hasUsername", ConstructorParameterDescription(_data.hasUsername)), ("forum", ConstructorParameterDescription(_data.forum)), ("userAdminRights", ConstructorParameterDescription(_data.userAdminRights)), ("botAdminRights", ConstructorParameterDescription(_data.botAdminRights))])
            case .requestPeerTypeCreateBot(let _data):
                return ("requestPeerTypeCreateBot", [("flags", ConstructorParameterDescription(_data.flags)), ("suggestedName", ConstructorParameterDescription(_data.suggestedName)), ("suggestedUsername", ConstructorParameterDescription(_data.suggestedUsername))])
            case .requestPeerTypeUser(let _data):
                return ("requestPeerTypeUser", [("flags", ConstructorParameterDescription(_data.flags)), ("bot", ConstructorParameterDescription(_data.bot)), ("premium", ConstructorParameterDescription(_data.premium))])
            }
        }

        public static func parse_requestPeerTypeBroadcast(_ reader: BufferReader) -> RequestPeerType? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Bool?
            if Int(_1!) & Int(1 << 3) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.Bool
                }
            }
            var _3: Api.ChatAdminRights?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.ChatAdminRights
                }
            }
            var _4: Api.ChatAdminRights?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.ChatAdminRights
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 3) == 0) || _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 1) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 2) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.RequestPeerType.requestPeerTypeBroadcast(Cons_requestPeerTypeBroadcast(flags: _1!, hasUsername: _2, userAdminRights: _3, botAdminRights: _4))
            }
            else {
                return nil
            }
        }
        public static func parse_requestPeerTypeChat(_ reader: BufferReader) -> RequestPeerType? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Bool?
            if Int(_1!) & Int(1 << 3) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.Bool
                }
            }
            var _3: Api.Bool?
            if Int(_1!) & Int(1 << 4) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.Bool
                }
            }
            var _4: Api.ChatAdminRights?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.ChatAdminRights
                }
            }
            var _5: Api.ChatAdminRights?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _5 = Api.parse(reader, signature: signature) as? Api.ChatAdminRights
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 3) == 0) || _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 4) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 2) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.RequestPeerType.requestPeerTypeChat(Cons_requestPeerTypeChat(flags: _1!, hasUsername: _2, forum: _3, userAdminRights: _4, botAdminRights: _5))
            }
            else {
                return nil
            }
        }
        public static func parse_requestPeerTypeCreateBot(_ reader: BufferReader) -> RequestPeerType? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            if Int(_1!) & Int(1 << 1) != 0 {
                _2 = parseString(reader)
            }
            var _3: String?
            if Int(_1!) & Int(1 << 2) != 0 {
                _3 = parseString(reader)
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 1) == 0) || _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 2) == 0) || _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.RequestPeerType.requestPeerTypeCreateBot(Cons_requestPeerTypeCreateBot(flags: _1!, suggestedName: _2, suggestedUsername: _3))
            }
            else {
                return nil
            }
        }
        public static func parse_requestPeerTypeUser(_ reader: BufferReader) -> RequestPeerType? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Bool?
            if Int(_1!) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.Bool
                }
            }
            var _3: Api.Bool?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.Bool
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 0) == 0) || _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 1) == 0) || _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.RequestPeerType.requestPeerTypeUser(Cons_requestPeerTypeUser(flags: _1!, bot: _2, premium: _3))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum RequestedPeer: TypeConstructorDescription {
        public class Cons_requestedPeerChannel: TypeConstructorDescription {
            public var flags: Int32
            public var channelId: Int64
            public var title: String?
            public var username: String?
            public var photo: Api.Photo?
            public init(flags: Int32, channelId: Int64, title: String?, username: String?, photo: Api.Photo?) {
                self.flags = flags
                self.channelId = channelId
                self.title = title
                self.username = username
                self.photo = photo
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestedPeerChannel", [("flags", ConstructorParameterDescription(self.flags)), ("channelId", ConstructorParameterDescription(self.channelId)), ("title", ConstructorParameterDescription(self.title)), ("username", ConstructorParameterDescription(self.username)), ("photo", ConstructorParameterDescription(self.photo))])
            }
        }
        public class Cons_requestedPeerChat: TypeConstructorDescription {
            public var flags: Int32
            public var chatId: Int64
            public var title: String?
            public var photo: Api.Photo?
            public init(flags: Int32, chatId: Int64, title: String?, photo: Api.Photo?) {
                self.flags = flags
                self.chatId = chatId
                self.title = title
                self.photo = photo
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestedPeerChat", [("flags", ConstructorParameterDescription(self.flags)), ("chatId", ConstructorParameterDescription(self.chatId)), ("title", ConstructorParameterDescription(self.title)), ("photo", ConstructorParameterDescription(self.photo))])
            }
        }
        public class Cons_requestedPeerUser: TypeConstructorDescription {
            public var flags: Int32
            public var userId: Int64
            public var firstName: String?
            public var lastName: String?
            public var username: String?
            public var photo: Api.Photo?
            public init(flags: Int32, userId: Int64, firstName: String?, lastName: String?, username: String?, photo: Api.Photo?) {
                self.flags = flags
                self.userId = userId
                self.firstName = firstName
                self.lastName = lastName
                self.username = username
                self.photo = photo
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requestedPeerUser", [("flags", ConstructorParameterDescription(self.flags)), ("userId", ConstructorParameterDescription(self.userId)), ("firstName", ConstructorParameterDescription(self.firstName)), ("lastName", ConstructorParameterDescription(self.lastName)), ("username", ConstructorParameterDescription(self.username)), ("photo", ConstructorParameterDescription(self.photo))])
            }
        }
        case requestedPeerChannel(Cons_requestedPeerChannel)
        case requestedPeerChat(Cons_requestedPeerChat)
        case requestedPeerUser(Cons_requestedPeerUser)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .requestedPeerChannel(let _data):
                if boxed {
                    buffer.appendInt32(-1952185372)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.channelId, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.username!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.photo!.serialize(buffer, true)
                }
                break
            case .requestedPeerChat(let _data):
                if boxed {
                    buffer.appendInt32(1929860175)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.chatId, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.photo!.serialize(buffer, true)
                }
                break
            case .requestedPeerUser(let _data):
                if boxed {
                    buffer.appendInt32(-701500310)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.userId, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.firstName!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.lastName!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.username!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.photo!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .requestedPeerChannel(let _data):
                return ("requestedPeerChannel", [("flags", ConstructorParameterDescription(_data.flags)), ("channelId", ConstructorParameterDescription(_data.channelId)), ("title", ConstructorParameterDescription(_data.title)), ("username", ConstructorParameterDescription(_data.username)), ("photo", ConstructorParameterDescription(_data.photo))])
            case .requestedPeerChat(let _data):
                return ("requestedPeerChat", [("flags", ConstructorParameterDescription(_data.flags)), ("chatId", ConstructorParameterDescription(_data.chatId)), ("title", ConstructorParameterDescription(_data.title)), ("photo", ConstructorParameterDescription(_data.photo))])
            case .requestedPeerUser(let _data):
                return ("requestedPeerUser", [("flags", ConstructorParameterDescription(_data.flags)), ("userId", ConstructorParameterDescription(_data.userId)), ("firstName", ConstructorParameterDescription(_data.firstName)), ("lastName", ConstructorParameterDescription(_data.lastName)), ("username", ConstructorParameterDescription(_data.username)), ("photo", ConstructorParameterDescription(_data.photo))])
            }
        }

        public static func parse_requestedPeerChannel(_ reader: BufferReader) -> RequestedPeer? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _3 = parseString(reader)
            }
            var _4: String?
            if Int(_1!) & Int(1 << 1) != 0 {
                _4 = parseString(reader)
            }
            var _5: Api.Photo?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _5 = Api.parse(reader, signature: signature) as? Api.Photo
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 2) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.RequestedPeer.requestedPeerChannel(Cons_requestedPeerChannel(flags: _1!, channelId: _2!, title: _3, username: _4, photo: _5))
            }
            else {
                return nil
            }
        }
        public static func parse_requestedPeerChat(_ reader: BufferReader) -> RequestedPeer? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _3 = parseString(reader)
            }
            var _4: Api.Photo?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.Photo
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 2) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.RequestedPeer.requestedPeerChat(Cons_requestedPeerChat(flags: _1!, chatId: _2!, title: _3, photo: _4))
            }
            else {
                return nil
            }
        }
        public static func parse_requestedPeerUser(_ reader: BufferReader) -> RequestedPeer? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _3 = parseString(reader)
            }
            var _4: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _4 = parseString(reader)
            }
            var _5: String?
            if Int(_1!) & Int(1 << 1) != 0 {
                _5 = parseString(reader)
            }
            var _6: Api.Photo?
            if Int(_1!) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _6 = Api.parse(reader, signature: signature) as? Api.Photo
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1!) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1!) & Int(1 << 0) == 0) || _4 != nil
            let _c5 = (Int(_1!) & Int(1 << 1) == 0) || _5 != nil
            let _c6 = (Int(_1!) & Int(1 << 2) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.RequestedPeer.requestedPeerUser(Cons_requestedPeerUser(flags: _1!, userId: _2!, firstName: _3, lastName: _4, username: _5, photo: _6))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum RequirementToContact: TypeConstructorDescription {
        public class Cons_requirementToContactPaidMessages: TypeConstructorDescription {
            public var starsAmount: Int64
            public init(starsAmount: Int64) {
                self.starsAmount = starsAmount
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("requirementToContactPaidMessages", [("starsAmount", ConstructorParameterDescription(self.starsAmount))])
            }
        }
        case requirementToContactEmpty
        case requirementToContactPaidMessages(Cons_requirementToContactPaidMessages)
        case requirementToContactPremium

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .requirementToContactEmpty:
                if boxed {
                    buffer.appendInt32(84580409)
                }
                break
            case .requirementToContactPaidMessages(let _data):
                if boxed {
                    buffer.appendInt32(-1258914157)
                }
                serializeInt64(_data.starsAmount, buffer: buffer, boxed: false)
                break
            case .requirementToContactPremium:
                if boxed {
                    buffer.appendInt32(-444472087)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .requirementToContactEmpty:
                return ("requirementToContactEmpty", [])
            case .requirementToContactPaidMessages(let _data):
                return ("requirementToContactPaidMessages", [("starsAmount", ConstructorParameterDescription(_data.starsAmount))])
            case .requirementToContactPremium:
                return ("requirementToContactPremium", [])
            }
        }

        public static func parse_requirementToContactEmpty(_ reader: BufferReader) -> RequirementToContact? {
            return Api.RequirementToContact.requirementToContactEmpty
        }
        public static func parse_requirementToContactPaidMessages(_ reader: BufferReader) -> RequirementToContact? {
            var _1: Int64?
            _1 = reader.readInt64()
            let _c1 = _1 != nil
            if _c1 {
                return Api.RequirementToContact.requirementToContactPaidMessages(Cons_requirementToContactPaidMessages(starsAmount: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_requirementToContactPremium(_ reader: BufferReader) -> RequirementToContact? {
            return Api.RequirementToContact.requirementToContactPremium
        }
    }
}
public extension Api {
    enum RestrictionReason: TypeConstructorDescription {
        public class Cons_restrictionReason: TypeConstructorDescription {
            public var platform: String
            public var reason: String
            public var text: String
            public init(platform: String, reason: String, text: String) {
                self.platform = platform
                self.reason = reason
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("restrictionReason", [("platform", ConstructorParameterDescription(self.platform)), ("reason", ConstructorParameterDescription(self.reason)), ("text", ConstructorParameterDescription(self.text))])
            }
        }
        case restrictionReason(Cons_restrictionReason)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .restrictionReason(let _data):
                if boxed {
                    buffer.appendInt32(-797791052)
                }
                serializeString(_data.platform, buffer: buffer, boxed: false)
                serializeString(_data.reason, buffer: buffer, boxed: false)
                serializeString(_data.text, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .restrictionReason(let _data):
                return ("restrictionReason", [("platform", ConstructorParameterDescription(_data.platform)), ("reason", ConstructorParameterDescription(_data.reason)), ("text", ConstructorParameterDescription(_data.text))])
            }
        }

        public static func parse_restrictionReason(_ reader: BufferReader) -> RestrictionReason? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.RestrictionReason.restrictionReason(Cons_restrictionReason(platform: _1!, reason: _2!, text: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum RichText: TypeConstructorDescription {
        public class Cons_textAnchor: TypeConstructorDescription {
            public var text: Api.RichText
            public var name: String
            public init(text: Api.RichText, name: String) {
                self.text = text
                self.name = name
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textAnchor", [("text", ConstructorParameterDescription(self.text)), ("name", ConstructorParameterDescription(self.name))])
            }
        }
        public class Cons_textBold: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textBold", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textConcat: TypeConstructorDescription {
            public var texts: [Api.RichText]
            public init(texts: [Api.RichText]) {
                self.texts = texts
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textConcat", [("texts", ConstructorParameterDescription(self.texts))])
            }
        }
        public class Cons_textEmail: TypeConstructorDescription {
            public var text: Api.RichText
            public var email: String
            public init(text: Api.RichText, email: String) {
                self.text = text
                self.email = email
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textEmail", [("text", ConstructorParameterDescription(self.text)), ("email", ConstructorParameterDescription(self.email))])
            }
        }
        public class Cons_textFixed: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textFixed", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textImage: TypeConstructorDescription {
            public var documentId: Int64
            public var w: Int32
            public var h: Int32
            public init(documentId: Int64, w: Int32, h: Int32) {
                self.documentId = documentId
                self.w = w
                self.h = h
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textImage", [("documentId", ConstructorParameterDescription(self.documentId)), ("w", ConstructorParameterDescription(self.w)), ("h", ConstructorParameterDescription(self.h))])
            }
        }
        public class Cons_textItalic: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textItalic", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textMarked: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textMarked", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textPhone: TypeConstructorDescription {
            public var text: Api.RichText
            public var phone: String
            public init(text: Api.RichText, phone: String) {
                self.text = text
                self.phone = phone
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textPhone", [("text", ConstructorParameterDescription(self.text)), ("phone", ConstructorParameterDescription(self.phone))])
            }
        }
        public class Cons_textPlain: TypeConstructorDescription {
            public var text: String
            public init(text: String) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textPlain", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textStrike: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textStrike", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textSubscript: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textSubscript", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textSuperscript: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textSuperscript", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textUnderline: TypeConstructorDescription {
            public var text: Api.RichText
            public init(text: Api.RichText) {
                self.text = text
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textUnderline", [("text", ConstructorParameterDescription(self.text))])
            }
        }
        public class Cons_textUrl: TypeConstructorDescription {
            public var text: Api.RichText
            public var url: String
            public var webpageId: Int64
            public init(text: Api.RichText, url: String, webpageId: Int64) {
                self.text = text
                self.url = url
                self.webpageId = webpageId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("textUrl", [("text", ConstructorParameterDescription(self.text)), ("url", ConstructorParameterDescription(self.url)), ("webpageId", ConstructorParameterDescription(self.webpageId))])
            }
        }
        case textAnchor(Cons_textAnchor)
        case textBold(Cons_textBold)
        case textConcat(Cons_textConcat)
        case textEmail(Cons_textEmail)
        case textEmpty
        case textFixed(Cons_textFixed)
        case textImage(Cons_textImage)
        case textItalic(Cons_textItalic)
        case textMarked(Cons_textMarked)
        case textPhone(Cons_textPhone)
        case textPlain(Cons_textPlain)
        case textStrike(Cons_textStrike)
        case textSubscript(Cons_textSubscript)
        case textSuperscript(Cons_textSuperscript)
        case textUnderline(Cons_textUnderline)
        case textUrl(Cons_textUrl)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .textAnchor(let _data):
                if boxed {
                    buffer.appendInt32(894777186)
                }
                _data.text.serialize(buffer, true)
                serializeString(_data.name, buffer: buffer, boxed: false)
                break
            case .textBold(let _data):
                if boxed {
                    buffer.appendInt32(1730456516)
                }
                _data.text.serialize(buffer, true)
                break
            case .textConcat(let _data):
                if boxed {
                    buffer.appendInt32(2120376535)
                }
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.texts.count))
                for item in _data.texts {
                    item.serialize(buffer, true)
                }
                break
            case .textEmail(let _data):
                if boxed {
                    buffer.appendInt32(-564523562)
                }
                _data.text.serialize(buffer, true)
                serializeString(_data.email, buffer: buffer, boxed: false)
                break
            case .textEmpty:
                if boxed {
                    buffer.appendInt32(-599948721)
                }
                break
            case .textFixed(let _data):
                if boxed {
                    buffer.appendInt32(1816074681)
                }
                _data.text.serialize(buffer, true)
                break
            case .textImage(let _data):
                if boxed {
                    buffer.appendInt32(136105807)
                }
                serializeInt64(_data.documentId, buffer: buffer, boxed: false)
                serializeInt32(_data.w, buffer: buffer, boxed: false)
                serializeInt32(_data.h, buffer: buffer, boxed: false)
                break
            case .textItalic(let _data):
                if boxed {
                    buffer.appendInt32(-653089380)
                }
                _data.text.serialize(buffer, true)
                break
            case .textMarked(let _data):
                if boxed {
                    buffer.appendInt32(55281185)
                }
                _data.text.serialize(buffer, true)
                break
            case .textPhone(let _data):
                if boxed {
                    buffer.appendInt32(483104362)
                }
                _data.text.serialize(buffer, true)
                serializeString(_data.phone, buffer: buffer, boxed: false)
                break
            case .textPlain(let _data):
                if boxed {
                    buffer.appendInt32(1950782688)
                }
                serializeString(_data.text, buffer: buffer, boxed: false)
                break
            case .textStrike(let _data):
                if boxed {
                    buffer.appendInt32(-1678197867)
                }
                _data.text.serialize(buffer, true)
                break
            case .textSubscript(let _data):
                if boxed {
                    buffer.appendInt32(-311786236)
                }
                _data.text.serialize(buffer, true)
                break
            case .textSuperscript(let _data):
                if boxed {
                    buffer.appendInt32(-939827711)
                }
                _data.text.serialize(buffer, true)
                break
            case .textUnderline(let _data):
                if boxed {
                    buffer.appendInt32(-1054465340)
                }
                _data.text.serialize(buffer, true)
                break
            case .textUrl(let _data):
                if boxed {
                    buffer.appendInt32(1009288385)
                }
                _data.text.serialize(buffer, true)
                serializeString(_data.url, buffer: buffer, boxed: false)
                serializeInt64(_data.webpageId, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .textAnchor(let _data):
                return ("textAnchor", [("text", ConstructorParameterDescription(_data.text)), ("name", ConstructorParameterDescription(_data.name))])
            case .textBold(let _data):
                return ("textBold", [("text", ConstructorParameterDescription(_data.text))])
            case .textConcat(let _data):
                return ("textConcat", [("texts", ConstructorParameterDescription(_data.texts))])
            case .textEmail(let _data):
                return ("textEmail", [("text", ConstructorParameterDescription(_data.text)), ("email", ConstructorParameterDescription(_data.email))])
            case .textEmpty:
                return ("textEmpty", [])
            case .textFixed(let _data):
                return ("textFixed", [("text", ConstructorParameterDescription(_data.text))])
            case .textImage(let _data):
                return ("textImage", [("documentId", ConstructorParameterDescription(_data.documentId)), ("w", ConstructorParameterDescription(_data.w)), ("h", ConstructorParameterDescription(_data.h))])
            case .textItalic(let _data):
                return ("textItalic", [("text", ConstructorParameterDescription(_data.text))])
            case .textMarked(let _data):
                return ("textMarked", [("text", ConstructorParameterDescription(_data.text))])
            case .textPhone(let _data):
                return ("textPhone", [("text", ConstructorParameterDescription(_data.text)), ("phone", ConstructorParameterDescription(_data.phone))])
            case .textPlain(let _data):
                return ("textPlain", [("text", ConstructorParameterDescription(_data.text))])
            case .textStrike(let _data):
                return ("textStrike", [("text", ConstructorParameterDescription(_data.text))])
            case .textSubscript(let _data):
                return ("textSubscript", [("text", ConstructorParameterDescription(_data.text))])
            case .textSuperscript(let _data):
                return ("textSuperscript", [("text", ConstructorParameterDescription(_data.text))])
            case .textUnderline(let _data):
                return ("textUnderline", [("text", ConstructorParameterDescription(_data.text))])
            case .textUrl(let _data):
                return ("textUrl", [("text", ConstructorParameterDescription(_data.text)), ("url", ConstructorParameterDescription(_data.url)), ("webpageId", ConstructorParameterDescription(_data.webpageId))])
            }
        }

        public static func parse_textAnchor(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.RichText.textAnchor(Cons_textAnchor(text: _1!, name: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_textBold(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textBold(Cons_textBold(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textConcat(_ reader: BufferReader) -> RichText? {
            var _1: [Api.RichText]?
            if let _ = reader.readInt32() {
                _1 = Api.parseVector(reader, elementSignature: 0, elementType: Api.RichText.self)
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textConcat(Cons_textConcat(texts: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textEmail(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.RichText.textEmail(Cons_textEmail(text: _1!, email: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_textEmpty(_ reader: BufferReader) -> RichText? {
            return Api.RichText.textEmpty
        }
        public static func parse_textFixed(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textFixed(Cons_textFixed(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textImage(_ reader: BufferReader) -> RichText? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.RichText.textImage(Cons_textImage(documentId: _1!, w: _2!, h: _3!))
            }
            else {
                return nil
            }
        }
        public static func parse_textItalic(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textItalic(Cons_textItalic(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textMarked(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textMarked(Cons_textMarked(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textPhone(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.RichText.textPhone(Cons_textPhone(text: _1!, phone: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_textPlain(_ reader: BufferReader) -> RichText? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textPlain(Cons_textPlain(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textStrike(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textStrike(Cons_textStrike(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textSubscript(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textSubscript(Cons_textSubscript(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textSuperscript(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textSuperscript(Cons_textSuperscript(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textUnderline(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.RichText.textUnderline(Cons_textUnderline(text: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_textUrl(_ reader: BufferReader) -> RichText? {
            var _1: Api.RichText?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.RichText
            }
            var _2: String?
            _2 = parseString(reader)
            var _3: Int64?
            _3 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.RichText.textUrl(Cons_textUrl(text: _1!, url: _2!, webpageId: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum SavedContact: TypeConstructorDescription {
        public class Cons_savedPhoneContact: TypeConstructorDescription {
            public var phone: String
            public var firstName: String
            public var lastName: String
            public var date: Int32
            public init(phone: String, firstName: String, lastName: String, date: Int32) {
                self.phone = phone
                self.firstName = firstName
                self.lastName = lastName
                self.date = date
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("savedPhoneContact", [("phone", ConstructorParameterDescription(self.phone)), ("firstName", ConstructorParameterDescription(self.firstName)), ("lastName", ConstructorParameterDescription(self.lastName)), ("date", ConstructorParameterDescription(self.date))])
            }
        }
        case savedPhoneContact(Cons_savedPhoneContact)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .savedPhoneContact(let _data):
                if boxed {
                    buffer.appendInt32(289586518)
                }
                serializeString(_data.phone, buffer: buffer, boxed: false)
                serializeString(_data.firstName, buffer: buffer, boxed: false)
                serializeString(_data.lastName, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .savedPhoneContact(let _data):
                return ("savedPhoneContact", [("phone", ConstructorParameterDescription(_data.phone)), ("firstName", ConstructorParameterDescription(_data.firstName)), ("lastName", ConstructorParameterDescription(_data.lastName)), ("date", ConstructorParameterDescription(_data.date))])
            }
        }

        public static func parse_savedPhoneContact(_ reader: BufferReader) -> SavedContact? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: Int32?
            _4 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.SavedContact.savedPhoneContact(Cons_savedPhoneContact(phone: _1!, firstName: _2!, lastName: _3!, date: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum SavedDialog: TypeConstructorDescription {
        public class Cons_monoForumDialog: TypeConstructorDescription {
            public var flags: Int32
            public var peer: Api.Peer
            public var topMessage: Int32
            public var readInboxMaxId: Int32
            public var readOutboxMaxId: Int32
            public var unreadCount: Int32
            public var unreadReactionsCount: Int32
            public var draft: Api.DraftMessage?
            public init(flags: Int32, peer: Api.Peer, topMessage: Int32, readInboxMaxId: Int32, readOutboxMaxId: Int32, unreadCount: Int32, unreadReactionsCount: Int32, draft: Api.DraftMessage?) {
                self.flags = flags
                self.peer = peer
                self.topMessage = topMessage
                self.readInboxMaxId = readInboxMaxId
                self.readOutboxMaxId = readOutboxMaxId
                self.unreadCount = unreadCount
                self.unreadReactionsCount = unreadReactionsCount
                self.draft = draft
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("monoForumDialog", [("flags", ConstructorParameterDescription(self.flags)), ("peer", ConstructorParameterDescription(self.peer)), ("topMessage", ConstructorParameterDescription(self.topMessage)), ("readInboxMaxId", ConstructorParameterDescription(self.readInboxMaxId)), ("readOutboxMaxId", ConstructorParameterDescription(self.readOutboxMaxId)), ("unreadCount", ConstructorParameterDescription(self.unreadCount)), ("unreadReactionsCount", ConstructorParameterDescription(self.unreadReactionsCount)), ("draft", ConstructorParameterDescription(self.draft))])
            }
        }
        public class Cons_savedDialog: TypeConstructorDescription {
            public var flags: Int32
            public var peer: Api.Peer
            public var topMessage: Int32
            public init(flags: Int32, peer: Api.Peer, topMessage: Int32) {
                self.flags = flags
                self.peer = peer
                self.topMessage = topMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("savedDialog", [("flags", ConstructorParameterDescription(self.flags)), ("peer", ConstructorParameterDescription(self.peer)), ("topMessage", ConstructorParameterDescription(self.topMessage))])
            }
        }
        case monoForumDialog(Cons_monoForumDialog)
        case savedDialog(Cons_savedDialog)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .monoForumDialog(let _data):
                if boxed {
                    buffer.appendInt32(1681948327)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.peer.serialize(buffer, true)
                serializeInt32(_data.topMessage, buffer: buffer, boxed: false)
                serializeInt32(_data.readInboxMaxId, buffer: buffer, boxed: false)
                serializeInt32(_data.readOutboxMaxId, buffer: buffer, boxed: false)
                serializeInt32(_data.unreadCount, buffer: buffer, boxed: false)
                serializeInt32(_data.unreadReactionsCount, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.draft!.serialize(buffer, true)
                }
                break
            case .savedDialog(let _data):
                if boxed {
                    buffer.appendInt32(-1115174036)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.peer.serialize(buffer, true)
                serializeInt32(_data.topMessage, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .monoForumDialog(let _data):
                return ("monoForumDialog", [("flags", ConstructorParameterDescription(_data.flags)), ("peer", ConstructorParameterDescription(_data.peer)), ("topMessage", ConstructorParameterDescription(_data.topMessage)), ("readInboxMaxId", ConstructorParameterDescription(_data.readInboxMaxId)), ("readOutboxMaxId", ConstructorParameterDescription(_data.readOutboxMaxId)), ("unreadCount", ConstructorParameterDescription(_data.unreadCount)), ("unreadReactionsCount", ConstructorParameterDescription(_data.unreadReactionsCount)), ("draft", ConstructorParameterDescription(_data.draft))])
            case .savedDialog(let _data):
                return ("savedDialog", [("flags", ConstructorParameterDescription(_data.flags)), ("peer", ConstructorParameterDescription(_data.peer)), ("topMessage", ConstructorParameterDescription(_data.topMessage))])
            }
        }

        public static func parse_monoForumDialog(_ reader: BufferReader) -> SavedDialog? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Peer?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.Peer
            }
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int32?
            _5 = reader.readInt32()
            var _6: Int32?
            _6 = reader.readInt32()
            var _7: Int32?
            _7 = reader.readInt32()
            var _8: Api.DraftMessage?
            if Int(_1!) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _8 = Api.parse(reader, signature: signature) as? Api.DraftMessage
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = (Int(_1!) & Int(1 << 1) == 0) || _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.SavedDialog.monoForumDialog(Cons_monoForumDialog(flags: _1!, peer: _2!, topMessage: _3!, readInboxMaxId: _4!, readOutboxMaxId: _5!, unreadCount: _6!, unreadReactionsCount: _7!, draft: _8))
            }
            else {
                return nil
            }
        }
        public static func parse_savedDialog(_ reader: BufferReader) -> SavedDialog? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Peer?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.Peer
            }
            var _3: Int32?
            _3 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.SavedDialog.savedDialog(Cons_savedDialog(flags: _1!, peer: _2!, topMessage: _3!))
            }
            else {
                return nil
            }
        }
    }
}
