// BlockLogFile: the text of one date file of the block log
// (activity_tracking.md §4.2; data_and_sync.md §6).

/// One date file: a header line, then one block per line in the order of `s`.
public enum BlockLogFile {
    /// The format number. Breaking changes to format 1 are allowed until
    /// the app's first release.
    public static let format = 1

    /// The header line: the format number and, for a person reading the
    /// file, the key legend. Readers skip it like any line without `s`.
    public static let header = #"{"format":1,"keys":{"s":"start","e":"end","r":"endReason","rc":"reconstructedSeconds","#
        + #""f":"foreground","b":"background","d":"device","t":"seconds","a":"app","i":"appID","w":"window","#
        + #""h":"host","ss":"session","l":"location","dc":"documents","c":"command","ws":"workspace"}}"#

    /// The text of a date file holding `blocks`: the header, then the blocks
    /// by start, each line ending in a newline.
    public static func text(of blocks: [ActivityBlock]) -> String {
        let lines = blocks.sorted { $0.start < $1.start }.map(\.jsonText)
        return ([header] + lines).map { $0 + "\n" }.joined()
    }

    /// Whether `text` starts with the current header line; a file in an
    /// older format is rewritten by the next rebuild of its date.
    public static func hasCurrentHeader(_ text: String) -> Bool {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) == header
    }

    /// The blocks of a date file and the number of lines that look like
    /// blocks but can't be read. The header and other lines without `s`
    /// are skipped.
    public static func parse(_ text: String) -> (blocks: [ActivityBlock], malformedLines: Int) {
        var blocks: [ActivityBlock] = []
        var malformed = 0
        for line in text.split(whereSeparator: \.isNewline) where !line.allSatisfy(\.isWhitespace) {
            guard let object = ActivityBlock.jsonObject(line) else {
                malformed += 1
                continue
            }
            guard object["s"] != nil else {
                continue
            }
            if let block = ActivityBlock(json: object) {
                blocks.append(block)
            } else {
                malformed += 1
            }
        }
        return (blocks, malformed)
    }

    /// `text` with `change` applied to each block: a block it returns
    /// unchanged keeps its line byte for byte, a changed one is written
    /// anew, and `nil` removes the line. Lines that are not blocks stay.
    public static func editing(_ text: String, _ change: (ActivityBlock) -> ActivityBlock?) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let block = ActivityBlock(jsonLine: line) else {
                lines.append(String(line))
                continue
            }
            guard let changed = change(block) else {
                continue
            }
            lines.append(changed == block ? String(line) : changed.jsonText)
        }
        return lines.joined(separator: "\n")
    }
}
