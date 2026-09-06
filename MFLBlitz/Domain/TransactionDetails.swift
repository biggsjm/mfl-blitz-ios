import Foundation
import MFLCore

/// Each MFL transaction type has its own wire layout. In particular a BBID
/// result is add|amount|drop, not the add|drop format used by free-agent moves.
struct TransactionDetails: Equatable, Sendable {
    struct Move: Equatable, Sendable {
        let label: String
        let codes: [String]
    }
    var moves: [Move] = []
    var bid: Decimal?
    var partnerID: String?

    init(type: String, fields: [String: MFLJSONValue]) {
        func codes(_ raw: String?) -> [String] {
            (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !["0", "0000"].contains($0) }
        }
        func move(_ label: String, _ raw: String?) {
            let ids = codes(raw)
            if !ids.isEmpty { moves.append(Move(label: label, codes: ids)) }
        }
        let parts = (fields["transaction"]?.stringValue ?? "").components(separatedBy: "|")
        switch type {
        case "BBID_WAIVER":
            guard parts.count >= 2 else { return }
            move("Added", parts[0])
            let amount = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if amount.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil {
                bid = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
            }
            if parts.count > 2 { move("Dropped", parts[2]) }
        case "FREE_AGENT":
            guard parts.count >= 2 else { return }
            move("Added", parts[0]); move("Dropped", parts[1])
        case "TRADE":
            partnerID = fields["franchise2"]?.stringValue
            move("Sent", fields["franchise1_gave_up"]?.stringValue)
            move("Received", fields["franchise2_gave_up"]?.stringValue)
        case "IR":
            move("Activated from IR", fields["activated"]?.stringValue)
            move("Placed on IR", fields["deactivated"]?.stringValue)
        case "TAXI":
            move("Promoted from taxi", fields["promoted"]?.stringValue)
            move("Moved to taxi", fields["demoted"]?.stringValue)
        default:
            // Do not guess positional fields for other transaction formats.
            break
        }
    }
}
