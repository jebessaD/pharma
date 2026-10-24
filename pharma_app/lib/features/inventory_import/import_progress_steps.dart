import 'dart:async';

import 'package:flutter/material.dart';

/// Visual state for one step in a multi-phase import flow.
enum ImportStepState { pending, active, done }

/// One labeled step (e.g. "Uploading photo").
class ImportProgressStep {
  const ImportProgressStep({required this.label, required this.state});

  final String label;
  final ImportStepState state;
}

/// Friendly rotating status while extraction runs (no step checklist).
class ImportWaitingCard extends StatefulWidget {
  const ImportWaitingCard({
    super.key,
    this.headline = 'Working on your photo',
    this.statusLine,
    this.rotateMessages = true,
    this.rotateHeadline = false,
    this.messages,
    this.stepDelaysMs,
  });

  final String headline;
  final String? statusLine;

  /// When true, cycles [messages] in the detail line below [headline].
  final bool rotateMessages;

  /// When true, [headline] is hidden and [messages] rotate as the main text.
  final bool rotateHeadline;

  /// Custom rotation list; defaults to [_defaultWaitMessages].
  final List<String>? messages;

  static const _defaultWaitMessages = [
    'Reading…',
    'Still reading…',
    'This might take a bit longer…',
    'Completing analysis…',
    'Just a moment…',
    'Almost there…',
  ];

  /// Milliseconds to wait on each message before advancing (one per step).
  /// Tuned for ~60s extraction: five uneven gaps before landing on "Almost there…".
  static const _defaultStepDelaysMs = [12000, 15000, 18000, 14000, 11000];

  List<String> get _messages => messages ?? _defaultWaitMessages;

  List<int> get _stepDelaysMs {
    final custom = stepDelaysMs;
    if (custom != null && custom.isNotEmpty) return custom;
    return _defaultStepDelaysMs;
  }

  /// Optional per-step delays in ms (length should be messages.length - 1).
  final List<int>? stepDelaysMs;

  @override
  State<ImportWaitingCard> createState() => _ImportWaitingCardState();
}

class _ImportWaitingCardState extends State<ImportWaitingCard> {
  Timer? _timer;
  int _messageIndex = 0;

  bool get _shouldRotate =>
      widget.rotateHeadline ||
      (widget.rotateMessages && widget.statusLine == null);

  @override
  void initState() {
    super.initState();
    if (_shouldRotate) {
      _scheduleNextStep();
    }
  }

  @override
  void didUpdateWidget(covariant ImportWaitingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRotating = oldWidget.rotateHeadline ||
        (oldWidget.rotateMessages && oldWidget.statusLine == null);
    if (_shouldRotate && !wasRotating) {
      _messageIndex = 0;
      _scheduleNextStep();
    } else if (!_shouldRotate && wasRotating) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNextStep() {
    _timer?.cancel();
    final messages = widget._messages;
    if (_messageIndex >= messages.length - 1) return;

    final delays = widget._stepDelaysMs;
    final delayMs = _messageIndex < delays.length
        ? delays[_messageIndex]
        : (delays.isEmpty ? 4000 : delays.last);

    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_messageIndex >= messages.length - 1) return;
      setState(() => _messageIndex++);
      _scheduleNextStep();
    });
  }

  String get _rotatingText => widget._messages[_messageIndex];

  String get _detail {
    if (widget.statusLine != null && widget.statusLine!.isNotEmpty) {
      return widget.statusLine!;
    }
    if (widget.rotateMessages && !widget.rotateHeadline) {
      return _rotatingText;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mainText = widget.rotateHeadline ? _rotatingText : widget.headline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: Text(
              mainText,
              key: ValueKey(mainText),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                _detail,
                key: ValueKey(_detail),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact banner with determinate progress (e.g. medicine matching).
class ImportDeterminateProgressBanner extends StatelessWidget {
  const ImportDeterminateProgressBanner({
    super.key,
    required this.title,
    required this.completed,
    required this.total,
  });

  final String title;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = total <= 0 ? null : (completed / total).clamp(0.0, 1.0);
    final countLabel = total <= 0 ? '' : '$completed of $total';
    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                ),
                if (countLabel.isNotEmpty)
                  Text(
                    countLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value, minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a number for total display (no decimals when whole).
String importFormatTotal(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

/// True when document grand total and summed line totals differ meaningfully.
bool importTotalsMismatch({required num? documentTotal, required num linesTotal}) {
  if (documentTotal == null || documentTotal <= 0) return false;
  if (linesTotal <= 0) return false;
  return (documentTotal - linesTotal).abs() > 1;
}

/// Sum of line totals: prefers qty × unit cost, else extracted line_total.
num importSumLineTotals(Iterable<({num? qty, num? unitCost, num? lineTotal})> rows) {
  var sum = 0.0;
  for (final row in rows) {
    final q = row.qty;
    final c = row.unitCost;
    if (q != null && c != null && q > 0) {
      sum += q * c;
    } else if (row.lineTotal != null && row.lineTotal! > 0) {
      sum += row.lineTotal!.toDouble();
    }
  }
  return sum;
}
