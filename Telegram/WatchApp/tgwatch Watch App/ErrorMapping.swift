import Foundation
import TDLibKit

func humanMessage(_ error: Swift.Error) -> String {
    if let tdErr = error as? TDLibKit.Error {
        return humanMessageForTdLibCode(tdErr.message)
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

private func humanMessageForTdLibCode(_ code: String) -> String {
    switch code {
    case "PHONE_NUMBER_INVALID":
        return "That phone number doesn't look right."
    case "PHONE_CODE_INVALID":
        return "That code is wrong."
    case "PHONE_CODE_EXPIRED":
        return "Code expired — request a new one."
    case "FIRSTNAME_INVALID":
        return "That first name doesn't look right."
    case "LASTNAME_INVALID":
        return "That last name doesn't look right."
    default:
        if code.hasPrefix("FLOOD_WAIT_") {
            let suffix = code.dropFirst("FLOOD_WAIT_".count)
            if let seconds = Int(suffix), seconds > 0 {
                return "Too many attempts. Wait \(seconds)s."
            }
            return "Too many attempts. Try again later."
        }
        return code
    }
}
