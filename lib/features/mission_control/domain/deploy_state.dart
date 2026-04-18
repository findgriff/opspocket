enum DeployStepStatus { pending, running, success, failure }

class DeployStep {
  final String label;
  final DeployStepStatus status;
  final String output;

  const DeployStep({
    required this.label,
    this.status = DeployStepStatus.pending,
    this.output = '',
  });

  DeployStep copyWith({DeployStepStatus? status, String? output}) => DeployStep(
        label: label,
        status: status ?? this.status,
        output: output ?? this.output,
      );
}

class DeployState {
  final List<DeployStep> steps;
  final bool isRunning;
  final bool done;
  final bool failed;

  const DeployState({
    required this.steps,
    this.isRunning = false,
    this.done = false,
    this.failed = false,
  });

  /// Index of the currently-running step, or -1 if none.
  int get activeStep =>
      steps.indexWhere((s) => s.status == DeployStepStatus.running);

  static DeployState initial() => const DeployState(
        steps: [
          DeployStep(label: 'Checking VPS'),
          DeployStep(label: 'Pulling latest code'),
          DeployStep(label: 'Installing packages'),
          DeployStep(label: 'Building'),
          DeployStep(label: 'Starting service'),
          DeployStep(label: 'Saving pm2 state'),
          DeployStep(label: 'Configuring Nginx'),
        ],
      );

  DeployState copyWith({
    List<DeployStep>? steps,
    bool? isRunning,
    bool? done,
    bool? failed,
  }) =>
      DeployState(
        steps: steps ?? this.steps,
        isRunning: isRunning ?? this.isRunning,
        done: done ?? this.done,
        failed: failed ?? this.failed,
      );
}
