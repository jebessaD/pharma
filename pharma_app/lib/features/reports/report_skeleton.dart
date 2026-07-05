import 'package:flutter/material.dart';

import 'report_ui.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 10,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = 0.35 + (_controller.value * 0.25);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: cs.outlineVariant.withValues(alpha: t),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

class ReportMoneySummarySkeleton extends StatelessWidget {
  const ReportMoneySummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile() {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: ReportUi.surfaceCard(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 34, height: 34, borderRadius: 12),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 48, height: 12),
                ],
              ),
              const SizedBox(height: 10),
              SkeletonBox(width: 96, height: 18),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [tile(), const SizedBox(width: 10), tile()]),
        const SizedBox(height: 10),
        Row(children: [tile(), const SizedBox(width: 10), tile()]),
      ],
    );
  }
}

class ReportInventorySkeleton extends StatelessWidget {
  const ReportInventorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: ReportUi.surfaceCard(cs),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: ReportUi.hairline(cs)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SkeletonBox(width: 32, height: 32, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 14)),
                  const SizedBox(width: 12),
                  SkeletonBox(width: 52, height: 14),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ReportResultsSkeleton extends StatelessWidget {
  const ReportResultsSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: ReportUi.surfaceCard(cs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: SkeletonBox(height: 18)),
                        const SizedBox(width: 12),
                        SkeletonBox(width: 72, height: 18),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SkeletonBox(height: 12, width: double.infinity),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
