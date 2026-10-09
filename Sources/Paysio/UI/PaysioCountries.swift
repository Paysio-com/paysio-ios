import Foundation

/// ISO 3166-1 alpha-2 country list for the billing address country picker, copied from
/// the React Native SDK (`ui/countries.ts`): the popular countries lead in the same
/// order as the web's CountrySelect, the rest are alphabetical. Flags are regional
/// indicator pairs, no artwork needed. US states come from `ui/usStates.ts`.
public enum PaysioCountries {
    public struct Country: Sendable, Equatable, Identifiable {
        public let code: String
        public let name: String
        public var id: String { code }
        public var flag: String { PaysioCountries.flagEmoji(code) }
    }

    public struct USState: Sendable, Equatable, Identifiable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    public static func flagEmoji(_ code: String) -> String {
        let cc = code.uppercased()
        guard cc.count == 2, cc.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
        return cc.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65).map(String.init) }.joined()
    }

    public static func countryName(_ code: String?) -> String {
        let cc = (code ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        guard !cc.isEmpty else { return "" }
        return list.first { $0.code == cc }?.name ?? cc
    }

    /// A US state code for a code or full name ("ny", "New York" -> "NY"); nil if unknown.
    public static func toUSStateCode(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        let upper = v.uppercased()
        if let byCode = usStates.first(where: { $0.code == upper }) { return byCode.code }
        let lower = v.lowercased()
        return usStates.first { $0.name.lowercased() == lower }?.code
    }

    private static let raw: [(String, String)] = [
        ("US", "United States"), ("CA", "Canada"), ("GB", "United Kingdom"), ("AU", "Australia"),
        ("NZ", "New Zealand"), ("IE", "Ireland"), ("DE", "Germany"), ("FR", "France"), ("ES", "Spain"),
        ("IT", "Italy"), ("NL", "Netherlands"), ("AF", "Afghanistan"), ("AX", "Åland Islands"), ("AL", "Albania"),
        ("DZ", "Algeria"), ("AS", "American Samoa"), ("AD", "Andorra"), ("AO", "Angola"), ("AI", "Anguilla"),
        ("AQ", "Antarctica"), ("AG", "Antigua & Barbuda"), ("AR", "Argentina"), ("AM", "Armenia"), ("AW", "Aruba"),
        ("AT", "Austria"), ("AZ", "Azerbaijan"), ("BS", "Bahamas"), ("BH", "Bahrain"), ("BD", "Bangladesh"),
        ("BB", "Barbados"), ("BY", "Belarus"), ("BE", "Belgium"), ("BZ", "Belize"), ("BJ", "Benin"), ("BM", "Bermuda"),
        ("BT", "Bhutan"), ("BO", "Bolivia"), ("BA", "Bosnia & Herzegovina"), ("BW", "Botswana"),
        ("BV", "Bouvet Island"), ("BR", "Brazil"), ("IO", "British Indian Ocean Territory"),
        ("VG", "British Virgin Islands"), ("BN", "Brunei"), ("BG", "Bulgaria"), ("BF", "Burkina Faso"),
        ("BI", "Burundi"), ("KH", "Cambodia"), ("CM", "Cameroon"), ("CV", "Cape Verde"),
        ("BQ", "Caribbean Netherlands"), ("KY", "Cayman Islands"), ("CF", "Central African Republic"), ("TD", "Chad"),
        ("CL", "Chile"), ("CN", "China"), ("CX", "Christmas Island"), ("CC", "Cocos (Keeling) Islands"),
        ("CO", "Colombia"), ("KM", "Comoros"), ("CG", "Congo - Brazzaville"), ("CD", "Congo - Kinshasa"),
        ("CK", "Cook Islands"), ("CR", "Costa Rica"), ("CI", "Côte d’Ivoire"), ("HR", "Croatia"), ("CU", "Cuba"),
        ("CW", "Curaçao"), ("CY", "Cyprus"), ("CZ", "Czechia"), ("DK", "Denmark"), ("DJ", "Djibouti"),
        ("DM", "Dominica"), ("DO", "Dominican Republic"), ("EC", "Ecuador"), ("EG", "Egypt"), ("SV", "El Salvador"),
        ("GQ", "Equatorial Guinea"), ("ER", "Eritrea"), ("EE", "Estonia"), ("SZ", "Eswatini"), ("ET", "Ethiopia"),
        ("FK", "Falkland Islands"), ("FO", "Faroe Islands"), ("FJ", "Fiji"), ("FI", "Finland"),
        ("GF", "French Guiana"), ("PF", "French Polynesia"), ("TF", "French Southern Territories"), ("GA", "Gabon"),
        ("GM", "Gambia"), ("GE", "Georgia"), ("GH", "Ghana"), ("GI", "Gibraltar"), ("GR", "Greece"),
        ("GL", "Greenland"), ("GD", "Grenada"), ("GP", "Guadeloupe"), ("GU", "Guam"), ("GT", "Guatemala"),
        ("GG", "Guernsey"), ("GN", "Guinea"), ("GW", "Guinea-Bissau"), ("GY", "Guyana"), ("HT", "Haiti"),
        ("HM", "Heard & McDonald Islands"), ("HN", "Honduras"), ("HK", "Hong Kong SAR China"), ("HU", "Hungary"),
        ("IS", "Iceland"), ("IN", "India"), ("ID", "Indonesia"), ("IR", "Iran"), ("IQ", "Iraq"), ("IM", "Isle of Man"),
        ("IL", "Israel"), ("JM", "Jamaica"), ("JP", "Japan"), ("JE", "Jersey"), ("JO", "Jordan"), ("KZ", "Kazakhstan"),
        ("KE", "Kenya"), ("KI", "Kiribati"), ("KW", "Kuwait"), ("KG", "Kyrgyzstan"), ("LA", "Laos"), ("LV", "Latvia"),
        ("LB", "Lebanon"), ("LS", "Lesotho"), ("LR", "Liberia"), ("LY", "Libya"), ("LI", "Liechtenstein"),
        ("LT", "Lithuania"), ("LU", "Luxembourg"), ("MO", "Macao SAR China"), ("MG", "Madagascar"), ("MW", "Malawi"),
        ("MY", "Malaysia"), ("MV", "Maldives"), ("ML", "Mali"), ("MT", "Malta"), ("MH", "Marshall Islands"),
        ("MQ", "Martinique"), ("MR", "Mauritania"), ("MU", "Mauritius"), ("YT", "Mayotte"), ("MX", "Mexico"),
        ("FM", "Micronesia"), ("MD", "Moldova"), ("MC", "Monaco"), ("MN", "Mongolia"), ("ME", "Montenegro"),
        ("MS", "Montserrat"), ("MA", "Morocco"), ("MZ", "Mozambique"), ("MM", "Myanmar (Burma)"), ("NA", "Namibia"),
        ("NR", "Nauru"), ("NP", "Nepal"), ("NC", "New Caledonia"), ("NI", "Nicaragua"), ("NE", "Niger"),
        ("NG", "Nigeria"), ("NU", "Niue"), ("NF", "Norfolk Island"), ("KP", "North Korea"), ("MK", "North Macedonia"),
        ("MP", "Northern Mariana Islands"), ("NO", "Norway"), ("OM", "Oman"), ("PK", "Pakistan"), ("PW", "Palau"),
        ("PS", "Palestinian Territories"), ("PA", "Panama"), ("PG", "Papua New Guinea"), ("PY", "Paraguay"),
        ("PE", "Peru"), ("PH", "Philippines"), ("PN", "Pitcairn Islands"), ("PL", "Poland"), ("PT", "Portugal"),
        ("PR", "Puerto Rico"), ("QA", "Qatar"), ("RE", "Réunion"), ("RO", "Romania"), ("RU", "Russia"),
        ("RW", "Rwanda"), ("WS", "Samoa"), ("SM", "San Marino"), ("ST", "São Tomé & Príncipe"), ("SA", "Saudi Arabia"),
        ("SN", "Senegal"), ("RS", "Serbia"), ("SC", "Seychelles"), ("SL", "Sierra Leone"), ("SG", "Singapore"),
        ("SX", "Sint Maarten"), ("SK", "Slovakia"), ("SI", "Slovenia"), ("SB", "Solomon Islands"), ("SO", "Somalia"),
        ("ZA", "South Africa"), ("GS", "South Georgia & South Sandwich Islands"), ("KR", "South Korea"),
        ("SS", "South Sudan"), ("LK", "Sri Lanka"), ("BL", "St. Barthélemy"), ("SH", "St. Helena"),
        ("KN", "St. Kitts & Nevis"), ("LC", "St. Lucia"), ("MF", "St. Martin"), ("PM", "St. Pierre & Miquelon"),
        ("VC", "St. Vincent & Grenadines"), ("SD", "Sudan"), ("SR", "Suriname"), ("SJ", "Svalbard & Jan Mayen"),
        ("SE", "Sweden"), ("CH", "Switzerland"), ("SY", "Syria"), ("TW", "Taiwan"), ("TJ", "Tajikistan"),
        ("TZ", "Tanzania"), ("TH", "Thailand"), ("TL", "Timor-Leste"), ("TG", "Togo"), ("TK", "Tokelau"),
        ("TO", "Tonga"), ("TT", "Trinidad & Tobago"), ("TN", "Tunisia"), ("TR", "Türkiye"), ("TM", "Turkmenistan"),
        ("TC", "Turks & Caicos Islands"), ("TV", "Tuvalu"), ("UM", "U.S. Outlying Islands"),
        ("VI", "U.S. Virgin Islands"), ("UG", "Uganda"), ("UA", "Ukraine"), ("AE", "United Arab Emirates"),
        ("UY", "Uruguay"), ("UZ", "Uzbekistan"), ("VU", "Vanuatu"), ("VA", "Vatican City"), ("VE", "Venezuela"),
        ("VN", "Vietnam"), ("WF", "Wallis & Futuna"), ("EH", "Western Sahara"), ("YE", "Yemen"), ("ZM", "Zambia"),
        ("ZW", "Zimbabwe"),
    ]

    public static let list: [Country] = raw.map { Country(code: $0.0, name: $0.1) }

    /// USPS codes the state picker offers: states, DC, territories, military.
    public static let usStates: [USState] = rawStates.map { USState(code: $0.0, name: $0.1) }

    private static let rawStates: [(String, String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"),
        ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"),
        ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"),
        ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"), ("MO", "Missouri"),
        ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"),
        ("NM", "New Mexico"), ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
        ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"),
        ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"),
        ("VA", "Virginia"), ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
        ("AS", "American Samoa"), ("GU", "Guam"), ("MP", "Northern Mariana Islands"), ("PR", "Puerto Rico"),
        ("VI", "U.S. Virgin Islands"), ("AA", "Armed Forces Americas"), ("AE", "Armed Forces Europe"),
        ("AP", "Armed Forces Pacific"),
    ]
}
