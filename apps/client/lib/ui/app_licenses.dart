import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kAppLicenseAsset = 'assets/legal/LICENSE.txt';
const kAppThirdPartyNoticesAsset = 'assets/legal/THIRD_PARTY_NOTICES.md';

const kAppLicenseShort =
    'Proprietary software of BackBenchDevs. All rights reserved.';

Future<void> showAppLicenses({required BuildContext context}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const AppLicensesDialog(),
  );
}

/// Firefox-style licenses viewer: product LICENSE + third-party notices.
class AppLicensesDialog extends StatefulWidget {
  const AppLicensesDialog({super.key});

  @override
  State<AppLicensesDialog> createState() => _AppLicensesDialogState();
}

class _AppLicensesDialogState extends State<AppLicensesDialog> {
  static const _tabs = ['Product', 'Third-party'];
  static const _copyright =
      'Copyright © 2026 BackBenchDevs. All rights reserved.';

  String? _product;
  String? _thirdParty;
  Object? _error;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final product = await rootBundle.loadString(kAppLicenseAsset);
      final third = await rootBundle.loadString(kAppThirdPartyNoticesAsset);
      if (!mounted) return;
      setState(() {
        _product = product;
        _thirdParty = third;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.35,
        );

    return Dialog(
      key: const Key('app-licenses-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Licenses',
                key: const Key('app-licenses-title'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                kAppLicenseShort,
                key: const Key('app-licenses-short'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              Text(
                _copyright,
                key: const Key('app-licenses-copyright'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < _tabs.length; i++)
                    ButtonSegment(value: i, label: Text(_tabs[i])),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: scheme.surfaceContainerLowest,
                  ),
                  child: _buildBody(bodyStyle),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('app-licenses-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TextStyle? bodyStyle) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Could not load license texts.\n$_error',
          key: const Key('app-licenses-error'),
          style: bodyStyle,
        ),
      );
    }
    final text = _tab == 0 ? (_product ?? '') : (_thirdParty ?? '');
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          key: Key(
            _tab == 0
                ? 'app-licenses-product-text'
                : 'app-licenses-third-party-text',
          ),
          style: bodyStyle,
        ),
      ),
    );
  }
}
