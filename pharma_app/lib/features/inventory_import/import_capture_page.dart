import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/pharmacy_profile_provider.dart';
import '../../core/providers/selected_branch_provider.dart';
import '../../core/roles/stock_permissions.dart';
import '../../core/widgets/form_error_banner.dart';
import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'import_error_text.dart';
import 'import_extraction_service.dart';
import 'import_logger.dart';
import 'import_models.dart';
import 'import_progress_steps.dart';
import 'import_review_session.dart';

enum _CapturePhase {
  openingPicker,
  uploading,
  analyzing,
  preparingReview,
}

/// Hub to start a stock/invoice import (file or photo), then review.
/// Reached via `/pharmacy/import-stock?mode=purchase|stock_in`.
class ImportCapturePage extends ConsumerStatefulWidget {
  const ImportCapturePage({
    super.key,
    required this.mode,
    this.missingSessionMessage,
    this.initialPhotoSource,
  });

  final ImportMode mode;
  final String? missingSessionMessage;

  /// When set, opens camera/gallery immediately (skips the chooser hub).
  final ImageSource? initialPhotoSource;

  @override
  ConsumerState<ImportCapturePage> createState() => _ImportCapturePageState();
}

class _ImportCapturePageState extends ConsumerState<ImportCapturePage> {
  final _service = ImportExtractionService();
  bool _busy = false;
  _CapturePhase? _phase;
  String? _error;
  Timer? _analyzePhaseTimer;
  ImageSource? _pickerSource;

  @override
  void initState() {
    super.initState();
    final msg = widget.missingSessionMessage;
    if (msg != null) {
      _error = msg;
    }
    final source = widget.initialPhotoSource;
    if (source != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(source);
      });
    }
  }

  @override
  void dispose() {
    _analyzePhaseTimer?.cancel();
    super.dispose();
  }

  void _setPhase(_CapturePhase phase) {
    if (!mounted) return;
    ImportLogger.phase(_phaseLabel());
    setState(() => _phase = phase);
  }

  String _phaseLabel() {
    return switch (_phase) {
      _CapturePhase.openingPicker => 'Opening photo',
      _CapturePhase.uploading => 'Sending photo',
      _CapturePhase.analyzing => 'Analyzing',
      _CapturePhase.preparingReview => 'Almost done',
      null => 'Please wait',
    };
  }

  bool get _rotateHeadline => _phase == _CapturePhase.analyzing;

  String _waitingHeadline() {
    return switch (_phase) {
      _CapturePhase.openingPicker => 'Opening photo',
      _CapturePhase.uploading => 'Sending photo',
      _CapturePhase.preparingReview => 'Almost done',
      _CapturePhase.analyzing || null => 'Please wait',
    };
  }

  String? _waitingStatusLine() {
    if (_phase == _CapturePhase.openingPicker) {
      return _pickerSource == ImageSource.camera
          ? 'Opening camera…'
          : 'Opening gallery…';
    }
    if (_phase == _CapturePhase.uploading) {
      return 'Uploading securely…';
    }
    if (_phase == _CapturePhase.preparingReview) {
      return 'Building your review form…';
    }
    return null;
  }

  bool get _rotateWaitMessages =>
      _phase == _CapturePhase.analyzing && !_rotateHeadline;

  String get _title =>
      widget.mode.isPurchase ? 'Import invoice' : 'Import stock';

  String get _subtitle => widget.mode.isPurchase
      ? 'Photo of a supplier invoice → purchase draft'
      : 'Excel/CSV or photo — then review before stock-in';

  bool get _directPhotoEntry => widget.initialPhotoSource != null;

  Future<void> _run(ImageSource source) async {
    if (_busy) return;
    final profile = ref.read(pharmacyProfileProvider).value;
    final teamId = profile?['team_id'] as String?;
    final role = profile?['role'] as String?;
    final branchId = ref.read(selectedBranchIdProvider);
    if (teamId == null || branchId == null) {
      setState(() => _error = 'Select a branch first.');
      return;
    }
    if (!canAddStockInForRole(role)) {
      setState(() => _error = 'Import is limited to team owners and admins.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _pickerSource = source;
      _phase = _CapturePhase.openingPicker;
    });
    try {
      final picked = await _service.pickImage(source: source);
      if (picked == null) {
        if (!mounted) return;
        // Entered from Stock in Take/Gallery — cancel returns there, not a 2nd hub.
        if (_directPhotoEntry) {
          context.pop();
          return;
        }
        setState(() {
          _busy = false;
          _phase = null;
        });
        return;
      }
      _setPhase(_CapturePhase.uploading);
      _analyzePhaseTimer?.cancel();
      _analyzePhaseTimer = Timer(const Duration(milliseconds: 600), () {
        if (_phase == _CapturePhase.uploading) {
          _setPhase(_CapturePhase.analyzing);
        }
      });
      final result = await _service.extract(image: picked, mode: widget.mode);
      _analyzePhaseTimer?.cancel();
      if (!mounted) return;
      if (result.lines.isEmpty) {
        setState(() {
          _busy = false;
          _phase = null;
          _error =
              'No medicine rows were found. Retake the photo with the full '
              'item table visible.';
        });
        return;
      }
      _setPhase(_CapturePhase.preparingReview);
      setImportReviewSession(
        ImportReviewSession(
          mode: widget.mode,
          extraction: result,
          teamId: teamId,
          branchId: branchId,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = null;
      });
      final committed = await context.push<bool>('/pharmacy/import-review');
      if (!mounted) return;
      // Always leave this page after review when opened as a direct photo hop.
      if (committed == true || _directPhotoEntry) {
        context.pop();
      }
    } catch (e, st) {
      _analyzePhaseTimer?.cancel();
      ImportLogger.error('Import capture failed', e, {'stack': '$st'});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = null;
        _error = importErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isPurchase = widget.mode.isPurchase;
    final directSource = widget.initialPhotoSource;

    return Scaffold(
      appBar: pharmacyPageAppBar(
        context,
        title: _title,
        subtitle: _directPhotoEntry
            ? (directSource == ImageSource.camera
                ? 'Take a photo of the stock table'
                : 'Pick a photo of the stock table')
            : _subtitle,
        actions: [
          if (!isPurchase && !_directPhotoEntry)
            IconButton(
              tooltip: 'Import history',
              onPressed: _busy
                  ? null
                  : () => context.push('/pharmacy/import-history'),
              icon: const Icon(Icons.history),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (_busy) ...[
            ImportWaitingCard(
              headline: _waitingHeadline(),
              statusLine: _waitingStatusLine(),
              rotateMessages: _rotateWaitMessages,
              rotateHeadline: _rotateHeadline,
            ),
          ] else if (_directPhotoEntry) ...[
            // No second chooser — only retry / leave after an error.
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _run(directSource!),
                icon: Icon(
                  directSource == ImageSource.camera
                      ? Icons.photo_camera_outlined
                      : Icons.photo_library_outlined,
                ),
                label: Text(
                  directSource == ImageSource.camera
                      ? 'Try camera again'
                      : 'Try gallery again',
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Back'),
              ),
            ],
          ] else if (isPurchase) ...[
            _BigChoiceButton(
              icon: Icons.photo_camera_outlined,
              title: 'Take invoice photo',
              subtitle: 'Camera · review before save',
              filled: true,
              onTap: () => _run(ImageSource.camera),
            ),
            const SizedBox(height: 12),
            _BigChoiceButton(
              icon: Icons.photo_library_outlined,
              title: 'Choose from gallery',
              subtitle: 'Existing invoice photo',
              filled: false,
              onTap: () => _run(ImageSource.gallery),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormErrorBanner(message: _error!),
            ],
          ] else ...[
            // Legacy entry (e.g. deep link without photo=) — send people to Stock in.
            Text(
              'Import from Stock in',
              style: t.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use the Import tab on Stock in to pick Excel, camera, or gallery.',
              style: t.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => context.go('/pharmacy/stock-in?tab=import'),
              child: const Text('Open Stock in · Import'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/pharmacy/import-history'),
              icon: const Icon(Icons.history),
              label: const Text('Import history & undo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormErrorBanner(message: _error!),
            ],
          ],
        ],
      ),
    );
  }
}

class _BigChoiceButton extends StatelessWidget {
  const _BigChoiceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    final bg = filled ? cs.primary : cs.surface;
    final fg = filled ? cs.onPrimary : cs.onSurface;
    final muted = filled
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.onSurfaceVariant;
    final border = filled
        ? BorderSide.none
        : BorderSide(color: cs.outlineVariant, width: 1.5);

    return Material(
      color: bg,
      elevation: filled ? 1 : 0,
      shadowColor: cs.shadow.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: border,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: filled
                      ? cs.onPrimary.withValues(alpha: 0.15)
                      : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: filled ? cs.onPrimary : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.textTheme.titleMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: muted, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
