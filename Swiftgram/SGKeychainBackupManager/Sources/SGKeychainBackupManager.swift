import Foundation
import Security

public enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidItemFormat
}

public class KeychainBackupManager {
    public static let shared = KeychainBackupManager()
    private let service = "\(Bundle.main.bundleIdentifier!).sessionsbackup"
    
    private init() {}
    
    // MARK: - Save Credentials
    public func saveSession(id: String, _ session: Data) throws {
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: session,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Add to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id
            ]
            
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: session
            ]
            
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary,
                                          attributesToUpdate as CFDictionary)
            
            if updateStatus != errSecSuccess {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }
    
    // MARK: - Retrieve Credentials
    public func retrieveSession(for id: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let sessionData = result as? Data else {
            throw KeychainError.itemNotFound
        }
        
        return sessionData
    }
    
    // MARK: - Delete Credentials
    public func deleteSession(for id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }
    
    // MARK: - Retrieve All Accounts
    public func getAllSessons() throws -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return []
        }
        
        guard status == errSecSuccess,
              let credentialsDataArray = result as? [Data] else {
            throw KeychainError.unknown(status)
        }
        
        return credentialsDataArray
    }
    
    // MARK: - Delete All Sessions
    public func deleteAllSessions() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // If no items were found, that's fine - just return
        if status == errSecItemNotFound {
            return
        }
        
        // For any other error, throw
        if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }
}
