import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_assets.dart';
import '../../core/onboarding/first_install_intro.dart';
import '../../core/shared_preferences_provider.dart';

class FirstInstallIntroPage extends ConsumerStatefulWidget {
  const FirstInstallIntroPage({super.key});

  @override
  ConsumerState<FirstInstallIntroPage> createState() =>
      _FirstInstallIntroPageState();
}

class _FirstInstallIntroPageState extends ConsumerState<FirstInstallIntroPage> {
  late final PageController _pageController;
  int _index = 0;
  bool _finishing = false;

  static const _slides = <_IntroSlideData>[
    _IntroSlideData(
      icon: Icons.storefront_rounded,
      imageAsset: AppAssets.welcomePharmacist,
      floatsAboveCircle: true,
      title: 'Welcome to Pharma Shelf',
      body: 'Sell, stock, expiry, and reports in one clean workspace.',
      badges: [
        _IntroBadgeData(icon: Icons.point_of_sale_rounded, label: 'Sell'),
        _IntroBadgeData(icon: Icons.inventory_2_rounded, label: 'Stock'),
        _IntroBadgeData(icon: Icons.insights_rounded, label: 'Insight'),
      ],
    ),
    _IntroSlideData(
      icon: Icons.inventory_2_rounded,
      imageAsset: AppAssets.inventoryCheck,
      title: 'Know what is on the shelf',
      body: 'Check stock, batches, and expiry dates at a glance.',
      badges: [
        _IntroBadgeData(icon: Icons.inventory_rounded, label: 'Count'),
        _IntroBadgeData(icon: Icons.qr_code_2_rounded, label: 'Batch'),
        _IntroBadgeData(icon: Icons.event_busy_rounded, label: 'Expiry'),
      ],
    ),
    _IntroSlideData(
      icon: Icons.rocket_launch_rounded,
      title: 'Start with confidence',
      body:
          'Create your pharmacy workspace, invite your team, and begin the day ready.',
      badges: [
        _IntroBadgeData(icon: Icons.task_alt_rounded, label: 'Setup'),
        _IntroBadgeData(icon: Icons.groups_2_rounded, label: 'Team'),
        _IntroBadgeData(icon: Icons.bolt_rounded, label: 'Ready'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final prefs = ref.read(sharedPreferencesProvider);
    await markFirstInstallIntroSeen(prefs);
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _next() async {
    if (_index == _slides.length - 1) {
      await _finish();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    if (_index == 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final isLast = _index == _slides.length - 1;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        AppAssets.logo,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pharma Shelf',
                          style: t.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _finishing ? null : _finish,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, index) {
                        return _IntroSlide(slide: _slides[index]);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Intro page ${_index + 1} of ${_slides.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slides.length, (dotIndex) {
                        final selected = dotIndex == _index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: selected ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: selected
                                ? cs.primary
                                : cs.outlineVariant.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _index == 0 || _finishing ? null : _back,
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _finishing ? null : _next,
                          child: Text(isLast ? 'Get started' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroSlideData {
  const _IntroSlideData({
    required this.icon,
    this.imageAsset,
    this.floatsAboveCircle = false,
    required this.title,
    required this.body,
    required this.badges,
  });

  final IconData icon;
  final String? imageAsset;
  final bool floatsAboveCircle;
  final String title;
  final String body;
  final List<_IntroBadgeData> badges;
}

class _IntroBadgeData {
  const _IntroBadgeData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _IntroSlide extends StatelessWidget {
  const _IntroSlide({required this.slide});

  final _IntroSlideData slide;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Stack(
      children: [
        Positioned.fill(child: _IntroBackground(slide: slide)),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 620;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: compact ? 10 : 24),
                    _HeroArtwork(slide: slide),
                    SizedBox(height: compact ? 18 : 30),
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      style: t.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.65,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.body,
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _PillStrip(items: slide.badges),
                    SizedBox(height: compact ? 12 : 24),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _IntroBackground extends StatelessWidget {
  const _IntroBackground({required this.slide});

  final _IntroSlideData slide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned(
          top: 76,
          right: 26,
          child: _FloatingIcon(icon: slide.icon, size: 54, color: cs.primary),
        ),
        Positioned(
          left: 22,
          bottom: 112,
          child: _FloatingIcon(
            icon: Icons.verified_user_rounded,
            size: 42,
            color: cs.tertiary,
          ),
        ),
      ],
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({required this.slide});

  final _IntroSlideData slide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imageAsset = slide.imageAsset;
    final showOrbitIcons = imageAsset == null || slide.floatsAboveCircle;

    if (imageAsset == null) {
      return _GetStartedArtwork(icon: slide.icon);
    }

    return Center(
      child: SizedBox(
        width: 300,
        height: 310,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 18,
              child: Container(
                width: 232,
                height: 232,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primaryContainer.withValues(alpha: 0.96),
                      cs.surfaceContainerHighest.withValues(alpha: 0.22),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.16),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              child: Container(
                width: 194,
                height: 194,
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            if (slide.floatsAboveCircle)
              Positioned(
                top: -42,
                left: 0,
                right: 0,
                child: ClipRect(
                  clipper: const _RightEdgeClipper(hiddenWidth: 2),
                  child: Image.asset(
                    imageAsset,
                    height: 338,
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                  ),
                ),
              )
            else
              Container(
                width: 228,
                height: 228,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    imageAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            if (showOrbitIcons) ...[
              Positioned(
                top: 50,
                left: 10,
                child: _FloatingIcon(
                  icon: Icons.trending_up_rounded,
                  size: 50,
                  color: cs.primary,
                ),
              ),
              Positioned(
                right: 6,
                top: 92,
                child: _FloatingIcon(
                  icon: Icons.health_and_safety_rounded,
                  size: 52,
                  color: cs.primary,
                ),
              ),
              Positioned(
                bottom: 52,
                left: 22,
                child: _FloatingIcon(
                  icon: Icons.medical_services_rounded,
                  size: 48,
                  color: cs.primary,
                ),
              ),
              Positioned(
                right: 24,
                bottom: 40,
                child: _FloatingIcon(
                  icon: Icons.groups_2_rounded,
                  size: 48,
                  color: cs.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GetStartedArtwork extends StatelessWidget {
  const _GetStartedArtwork({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Center(
      child: SizedBox(
        width: 320,
        height: 310,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 28,
              child: Container(
                width: 238,
                height: 238,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      cs.primaryContainer.withValues(alpha: 0.78),
                      cs.primary.withValues(alpha: 0.10),
                      cs.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 54,
              child: Container(
                width: 182,
                height: 182,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cs.primary, cs.tertiary.withValues(alpha: 0.88)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.24),
                      blurRadius: 36,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.96),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.onPrimary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Icon(icon, color: cs.primary, size: 54),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 76,
              child: _OrbitChip(
                icon: Icons.storefront_rounded,
                label: 'Setup',
                color: cs.primary,
              ),
            ),
            Positioned(
              right: 12,
              top: 138,
              child: _OrbitChip(
                icon: Icons.groups_2_rounded,
                label: 'Team',
                color: cs.tertiary,
              ),
            ),
            Positioned(
              left: 54,
              bottom: 52,
              child: _OrbitChip(
                icon: Icons.inventory_2_rounded,
                label: 'Stock',
                color: cs.secondary,
              ),
            ),
            Positioned(
              top: 32,
              right: 70,
              child: _SparkDot(size: 12, color: cs.primary),
            ),
            Positioned(
              left: 62,
              bottom: 92,
              child: _SparkDot(size: 8, color: cs.tertiary),
            ),
            Positioned(
              right: 76,
              bottom: 36,
              child: _SparkDot(size: 10, color: cs.secondary),
            ),
            Positioned(
              bottom: 12,
              child: Text(
                'Tap Get started to open your workspace',
                style: t.textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitChip extends StatelessWidget {
  const _OrbitChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: t.textTheme.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkDot extends StatelessWidget {
  const _SparkDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.78),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox(width: size, height: size),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  const _FloatingIcon({
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.52, color: color),
      ),
    );
  }
}

class _PillStrip extends StatelessWidget {
  const _PillStrip({required this.items});

  final List<_IntroBadgeData> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 17, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: t.textTheme.labelLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RightEdgeClipper extends CustomClipper<Rect> {
  const _RightEdgeClipper({required this.hiddenWidth});

  final double hiddenWidth;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      0,
      0,
      (size.width - hiddenWidth).clamp(0, size.width),
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _RightEdgeClipper oldClipper) {
    return oldClipper.hiddenWidth != hiddenWidth;
  }
}
