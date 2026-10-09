import Foundation

/// Client-side rules that mirror the server (CONTRACT.md section 3):
/// street, city, postal code and country for any manually entered card or bank;
/// email, first name and last name; phone when the workspace requires it.
public enum PaysioValidation {
    public static func validateContact(_ customer: PaysioCustomer, requirePhone: Bool) -> [PaysioField: String] {
        var errors: [PaysioField: String] = [:]
        if !isEmail(customer.email) { errors[.email] = "Enter a valid email address." }
        if customer.firstName.trimmed.isEmpty { errors[.firstName] = "Enter your first name." }
        if customer.lastName.trimmed.isEmpty { errors[.lastName] = "Enter your last name." }
        if requirePhone, (customer.phone ?? "").trimmed.count < 7 { errors[.phone] = "Enter your phone number." }
        return errors
    }

    public static func validateBillingAddress(_ address: PaysioAddress) -> [PaysioField: String] {
        var errors: [PaysioField: String] = [:]
        if address.address1.trimmed.isEmpty { errors[.address1] = "Enter your street address." }
        if address.city.trimmed.isEmpty { errors[.city] = "Enter your city." }
        if address.postalCode.trimmed.isEmpty { errors[.postalCode] = "Enter your postal code." }
        if address.country.trimmed.count != 2 { errors[.country] = "Choose your country." }
        if ["US", "CA"].contains(address.country.uppercased()), address.state.trimmed.isEmpty {
            errors[.state] = "Choose your state."
        }
        return errors
    }

    public static func isEmail(_ value: String) -> Bool {
        let v = value.trimmed
        guard let at = v.firstIndex(of: "@"), at > v.startIndex, at < v.index(before: v.endIndex) else { return false }
        let domain = v[v.index(after: at)...]
        return domain.contains(".") && !v.contains(" ")
    }

    /// ABA routing number: 9 digits and the standard checksum
    /// (3,7,1 weights; sum mod 10 == 0).
    public static func isRoutingNumber(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 9, digits == value.trimmed else { return false }
        let weights = [3, 7, 1, 3, 7, 1, 3, 7, 1]
        var sum = 0
        for (i, ch) in digits.enumerated() {
            guard let d = ch.wholeNumberValue else { return false }
            sum += d * weights[i]
        }
        return sum % 10 == 0
    }

    /// Bank account numbers: 4 to 17 digits (the US ACH range).
    public static func isAccountNumberLength(_ length: Int) -> Bool { (4...17).contains(length) }

    /// Luhn check used when we need to validate outside the VGS field (never on raw PAN
    /// from the field itself; the field validates itself).
    public static func luhn(_ digits: String) -> Bool {
        var sum = 0
        var double = false
        for ch in digits.reversed() {
            guard var d = ch.wholeNumberValue else { return false }
            if double { d *= 2; if d > 9 { d -= 9 } }
            sum += d
            double.toggle()
        }
        return !digits.isEmpty && sum % 10 == 0
    }

    /// Normalizes a VGS brand name to the identifiers the Paysio API and the brand
    /// marks use: `visa`, `mastercard`, `amex`, `discover`, `dinersclub`, `jcb`,
    /// `unionpay`, `maestro`, or the lowercase name as a fallback.
    public static func normalizeBrand(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let key = name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        switch key {
        case "visa", "visaelectron": return "visa"
        case "mastercard", "master", "mc": return "mastercard"
        case "amex", "americanexpress": return "amex"
        case "discover": return "discover"
        case "dinersclub", "diners": return "dinersclub"
        case "jcb": return "jcb"
        case "unionpay": return "unionpay"
        case "maestro": return "maestro"
        case "unknown", "": return nil
        default: return key
        }
    }

    /// Parses "MM/YY", "MM / YY" or "MM/YYYY" into ("MM", "YYYY").
    public static func parseExpiry(_ raw: String) -> (month: String, year: String)? {
        let parts = raw.split(whereSeparator: { $0 == "/" || $0 == "-" }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let m = Int(parts[0]), (1...12).contains(m), var y = Int(parts[1]) else { return nil }
        if y < 100 { y += 2000 }
        return (String(format: "%02d", m), String(y))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
