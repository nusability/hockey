/// A line of shared/vectors/season/save/manifest.txt (spec §15): a save file and the state it
/// holds — `<file> <season vector|-> <player matches|end> <drills won, comma-separated|-> <board|->`,
/// the board as `pressing covering push_up discipline formation period_seconds ball_spin_seconds`.
/// Both platforms build the state from the line and must write the file's bytes exactly.
public struct SaveVectorCase: Sendable {
    public let file: String
    public let save: SaveRecord

    /// `vector` reads a season vector's text by its file name.
    public init(line: String, vector: (String) throws -> String) throws {
        let w = line.split(separator: " ").map(String.init)
        guard w.count == 5 || w.count == 11 else { throw SeasonScript.Failure(description: "bad manifest line: \(line)") }
        file = w[0]
        var save = SaveRecord.fresh
        if w[1] != "-" {
            let script = try SeasonScript.parse(try vector(w[1]))
            save = try script.run(stopAfter: w[2] == "end" ? nil : Int(w[2])).save
        }
        if w[3] != "-" {
            for key in w[3].split(separator: ",") {
                guard let drill = Drill(rawValue: String(key)) else { throw SeasonScript.Failure(description: "bad drill: \(key)") }
                save.won(drill)
            }
        }
        if w.count == 11 {
            guard let f = Formation(rawValue: w[8]), let pressing = Double(w[4]), let covering = Double(w[5]),
                  let pushUp = Double(w[6]), let discipline = Double(w[7]), let period = Double(w[9]),
                  let spin = Double(w[10]) else { throw SeasonScript.Failure(description: "bad board: \(line)") }
            save.board = BoardRecord(pressing: pressing, covering: covering, pushUp: pushUp, discipline: discipline,
                                     formation: f, periodSeconds: period, ballSpinSeconds: spin)
        }
        self.save = save
    }
}
