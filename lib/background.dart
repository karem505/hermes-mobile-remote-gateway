/// Background work owned by the open session: `terminal(background=true)`
/// processes, delegated subagents and `/background` side agents.
///
/// Kept in its own library so both the store (which owns the lifecycle) and the
/// UI (which renders the strip) can depend on it without an import cycle.
/// Output kept per row. A chatty background process must not grow the strip
/// without bound: the newest tail is what matters.
const backgroundDetailLimit = 4000;

enum BackgroundState { running, done, failed }

class BackgroundActivity {
  BackgroundActivity({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.state = BackgroundState.running,
    this.detail = '',
    this.toolCount,
    this.model,
    this.exitCode,
  });

  /// `process_id`, `subagent_id` or `task_id` from the gateway.
  final String id;
  final String kind; // process | subagent | agent
  String title;
  String subtitle;
  BackgroundState state;

  /// Output tail, completion summary or side-agent answer.
  String detail;
  int? toolCount;
  String? model;
  int? exitCode;

  bool get running => state == BackgroundState.running;

  /// Subagent lifecycle → strip state. Anything unrecognised keeps the state the
  /// caller already had rather than inventing a transition.
  static BackgroundState stateForSubagent(String status, {BackgroundState? fallback}) => switch (status) {
        'queued' || 'running' => BackgroundState.running,
        'failed' || 'error' || 'timeout' || 'interrupted' => BackgroundState.failed,
        'completed' => BackgroundState.done,
        _ => fallback ?? BackgroundState.done,
      };

  /// Shell status → strip state. `exit_code` only matters once it has exited.
  static BackgroundState stateForProcess(String status, int? exitCode) {
    final live = status != 'exited' && status != 'closed' && status != 'done';
    if (live) return BackgroundState.running;
    return exitCode == null || exitCode == 0 ? BackgroundState.done : BackgroundState.failed;
  }

  static String firstLine(String s) => s.split('\n').first.trim();
}
