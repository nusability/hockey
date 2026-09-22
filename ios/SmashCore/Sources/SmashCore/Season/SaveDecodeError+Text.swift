extension SaveDecodeError: CustomStringConvertible {
    /// One line naming the kind and where: how logs show a refused save, and how
    /// shared/vectors/season/save/invalid.txt records the expected refusal (Android's
    /// `SaveDecodeError.toString()` writes the same).
    public var description: String {
        switch self {
        case .malformedJSON(let offset): "malformedJSON \(offset)"
        case .unknownVersion(let v): "unknownVersion \(v)"
        case .missingField(let path): "missingField \(path)"
        case .unknownField(let path): "unknownField \(path)"
        case .duplicateField(let path): "duplicateField \(path)"
        case .wrongType(let path): "wrongType \(path)"
        case .badValue(let path): "badValue \(path)"
        case .brokenRule(let path, let rule): "brokenRule \(path) \(rule.rawValue)"
        }
    }
}
