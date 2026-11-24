//
//  ProxyType.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// Describes the type of proxy server
public indirect enum ProxyType: Codable, Equatable, Hashable {

    /// A SOCKS5 proxy server
    case proxyTypeSocks5(ProxyTypeSocks5)

    /// A HTTP transparent proxy server
    case proxyTypeHttp(ProxyTypeHttp)

    /// An MTProto proxy server
    case proxyTypeMtproto(ProxyTypeMtproto)

    /// A web proxy server. MTProto traffic goes through an HTTPS relay page hosted by the application in a hidden web view; see updateWebProxyCarrierOpened. The proxy server must be a domain name and the port must be 443
    case proxyTypeWeb(ProxyTypeWeb)

    /// Decoded when the @type is not one of the known cases (forward-compatible).
    case unsupported

    private enum Kind: String, Codable {
        case proxyTypeSocks5
        case proxyTypeHttp
        case proxyTypeMtproto
        case proxyTypeWeb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = Kind(rawValue: typeString) else {
            self = .unsupported
            return
        }
        switch type {
        case .proxyTypeSocks5:
            let value = try ProxyTypeSocks5(from: decoder)
            self = .proxyTypeSocks5(value)
        case .proxyTypeHttp:
            let value = try ProxyTypeHttp(from: decoder)
            self = .proxyTypeHttp(value)
        case .proxyTypeMtproto:
            let value = try ProxyTypeMtproto(from: decoder)
            self = .proxyTypeMtproto(value)
        case .proxyTypeWeb:
            let value = try ProxyTypeWeb(from: decoder)
            self = .proxyTypeWeb(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .proxyTypeSocks5(let value):
            try container.encode(Kind.proxyTypeSocks5, forKey: .type)
            try value.encode(to: encoder)
        case .proxyTypeHttp(let value):
            try container.encode(Kind.proxyTypeHttp, forKey: .type)
            try value.encode(to: encoder)
        case .proxyTypeMtproto(let value):
            try container.encode(Kind.proxyTypeMtproto, forKey: .type)
            try value.encode(to: encoder)
        case .proxyTypeWeb(let value):
            try container.encode(Kind.proxyTypeWeb, forKey: .type)
            try value.encode(to: encoder)
        case .unsupported:
            try container.encode("unsupported", forKey: .type)
        }
    }
}

/// A SOCKS5 proxy server
public struct ProxyTypeSocks5: Codable, Equatable, Hashable {

    /// Password for logging in; may be empty
    public let password: String

    /// Username for logging in; may be empty
    public let username: String


    public init(
        password: String,
        username: String
    ) {
        self.password = password
        self.username = username
    }
}

/// A HTTP transparent proxy server
public struct ProxyTypeHttp: Codable, Equatable, Hashable {

    /// Pass true if the proxy supports only HTTP requests and doesn't support transparent TCP connections via HTTP CONNECT method
    public let httpOnly: Bool

    /// Password for logging in; may be empty
    public let password: String

    /// Username for logging in; may be empty
    public let username: String


    public init(
        httpOnly: Bool,
        password: String,
        username: String
    ) {
        self.httpOnly = httpOnly
        self.password = password
        self.username = username
    }
}

/// An MTProto proxy server
public struct ProxyTypeMtproto: Codable, Equatable, Hashable {

    /// The proxy's secret in hexadecimal encoding
    public let secret: String


    public init(secret: String) {
        self.secret = secret
    }
}

/// A web proxy server. MTProto traffic goes through an HTTPS relay page hosted by the application in a hidden web view; see updateWebProxyCarrierOpened. The proxy server must be a domain name and the port must be 443
public struct ProxyTypeWeb: Codable, Equatable, Hashable {

    /// Base path of the relay on the server, without leading and trailing slashes; may be empty. Consists of 0-128 characters; each "/"-separated segment must match [A-Za-z0-9][A-Za-z0-9_-]*
    public let path: String

    /// The MTProto proxy secret in hexadecimal encoding; must be 16 bytes long, optionally prefixed with the byte 0xdd
    public let secret: String


    public init(
        path: String,
        secret: String
    ) {
        self.path = path
        self.secret = secret
    }
}

