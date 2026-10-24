import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/pharmacy_page_app_bar.dart';
import 'create_purchase_page.dart';
import 'purchase_drafts_list_body.dart';

enum PurchasesHubTab { drafts, newPurchase }

/// `/pharmacy/purchases?tab=drafts|new` (default drafts). Legacy `/purchases/drafts` and `/purchases/new` redirect here.
class PurchasesHubPage extends StatelessWidget {
  const PurchasesHubPage({
    super.key,
    required this.initialTab,
    this.initialSupplierId,
  });

  final PurchasesHubTab initialTab;
  final String? initialSupplierId;

  @override
  Widget build(BuildContext context) {
    if (initialTab == PurchasesHubTab.newPurchase) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          context.go('/pharmacy/purchases');
        },
        child: Scaffold(
          appBar: pharmacyPageAppBar(
            context,
            title: 'New purchase',
            actions: [
              TextButton(
                onPressed: () => context.go('/pharmacy/purchases'),
                child: const Text('Drafts'),
              ),
            ],
          ),
          body: CreatePurchasePage(initialSupplierId: initialSupplierId),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'import_invoice',
            onPressed: () =>
                context.push('/pharmacy/import-stock?mode=purchase'),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Import photo'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new_purchase',
            onPressed: () => context.go('/pharmacy/purchases?tab=new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New purchase'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PharmacyPageHeader(
            title: 'Purchases',
            subtitle: 'Draft orders and receive stock',
          ),
          Expanded(
            child: PurchaseDraftsListBody(
              onCreatePurchase: () => context.go('/pharmacy/purchases?tab=new'),
            ),
          ),
        ],
      ),
    );
  }
}
