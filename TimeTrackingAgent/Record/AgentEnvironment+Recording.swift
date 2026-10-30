// AgentEnvironment+Recording: the seams that `--record` wraps
// (spec_activity_tracking.md §5, spec_architecture.md §3.4).

extension AgentEnvironment {
    /// This environment with its command and AppleScript runners recording
    /// every output to `recorder`.
    func recording(with recorder: Recorder) -> Self {
        var result = self
        result.commands = RecordingCommandRunner(base: commands, recorder: recorder)
        result.scripts = RecordingScripts(base: scripts, recorder: recorder)
        return result
    }
}
