import Foundation

/// Device-local storage for NexusNFT presentation data.
public final class NexusNFTStore {
    private let defaults: UserDefaults
    private let giftsKey = "nexusnft.gifts.v1"
    private let walletKey = "nexusnft.wallet.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func loadGifts() -> [NexusNFTGift] {
        guard let data = defaults.data(forKey: giftsKey),
              let gifts = try? decoder.decode([NexusNFTGift].self, from: data) else { return [] }
        return gifts.sorted { $0.sortIndex < $1.sortIndex }
    }

    public func saveGifts(_ gifts: [NexusNFTGift]) {
        guard let data = try? encoder.encode(gifts) else { return }
        defaults.set(data, forKey: giftsKey)
    }

    public func loadWallet() -> NexusNFTWallet {
        guard let data = defaults.data(forKey: walletKey),
              let wallet = try? decoder.decode(NexusNFTWallet.self, from: data) else { return NexusNFTWallet() }
        return wallet
    }

    public func saveWallet(_ wallet: NexusNFTWallet) {
        guard let data = try? encoder.encode(wallet) else { return }
        defaults.set(data, forKey: walletKey)
    }
}
