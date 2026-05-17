import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/forms/form_error_mapper.dart';
import '../../core/widgets/app_error_state.dart';
import 'receipt_download_share.dart';
import 'receipt_image_bytes.dart';
import 'sale_receipt_text.dart';

class SaleReceiptPage extends StatefulWidget {
  const SaleReceiptPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<SaleReceiptPage> createState() => _SaleReceiptPageState();
}

class _SaleReceiptPageState extends State<SaleReceiptPage> {
  bool _loading = true;
  bool _imageBuilding = false;
  String? _error;
  Map<String, dynamic>? _sale;
  String? _branchName;
  String? _sellerDisplayName;
  Uint8List? _receiptPngBytes;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _receiptPngBytes = null;
    });
    try {
      final sale = await Supabase.instance.client
          .from('sales')
          .select(
            'id, created_at, subtotal, discount_total, grand_total, branch_id, sold_by, '
            'sale_items(qty, unit_price, line_total, medicine_batches(batch_no, medicines(name))), '
            'payments(method, amount, reference_no)',
          )
          .eq('id', widget.saleId)
          .maybeSingle();
      if (!mounted) return;
      if (sale == null) {
        setState(() {
          _loading = false;
          _error = 'Sale not found or you do not have access.';
        });
        return;
      }
      final branchId = sale['branch_id'] as String?;
      String? bname;
      if (branchId != null) {
        final b = await Supabase.instance.client
            .from('branches')
            .select('name')
            .eq('id', branchId)
            .maybeSingle();
        bname = b?['name'] as String?;
      }
      final soldBy = sale['sold_by'] as String?;
      String? sellerName;
      if (soldBy != null && soldBy.isNotEmpty) {
        final prof = await Supabase.instance.client
            .from('profiles')
            .select('full_name, username')
            .eq('id', soldBy)
            .maybeSingle();
        if (prof != null) {
          final fn = (prof['full_name'] as String?)?.trim() ?? '';
          final un = (prof['username'] as String?)?.trim() ?? '';
          sellerName = fn.isNotEmpty
              ? fn
              : (un.isNotEmpty ? un : 'Team member');
        }
      }
      final row = Map<String, dynamic>.from(sale);
      if (!mounted) return;
      setState(() {
        _sale = row;
        _branchName = bname;
        _sellerDisplayName = sellerName;
        _loading = false;
        _imageBuilding = true;
      });
      await _buildReceiptPng(row, bname, sellerName);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _imageBuilding = false;
          _error = userFacingError(e);
        });
      }
    }
  }

  Future<void> _buildReceiptPng(
    Map<String, dynamic> sale,
    String? branchName,
    String? sellerName,
  ) async {
    Uint8List? bytes;
    try {
      final text = formatSaleReceiptText(
        sale: sale,
        branchName: branchName,
        sellerDisplayName: sellerName,
      );
      bytes = await buildReceiptPngBytes(text);
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    setState(() {
      _receiptPngBytes = bytes;
      _imageBuilding = false;
    });
  }

  String _buildReceiptText() {
    return formatSaleReceiptText(
      sale: _sale!,
      branchName: _branchName,
      sellerDisplayName: _sellerDisplayName,
    );
  }

  Future<void> _download() async {
    final png = _receiptPngBytes;
    if (png == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt image is not ready yet.')),
      );
      return;
    }
    final result = await saveReceiptPngToDevice(widget.saleId, png);
    if (!mounted) return;
    showReceiptSaveFeedback(context, widget.saleId, png, result);
  }

  Future<void> _share() async {
    final png = _receiptPngBytes;
    if (png != null) {
      try {
        await shareReceiptPngBytes(widget.saleId, png);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share receipt image.')),
        );
      }
      return;
    }
    try {
      await Share.share(_buildReceiptText(), subject: 'Pharmacy receipt');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share receipt.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = math.min(420.0, MediaQuery.sizeOf(context).width - 32);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : _sale == null
          ? const Center(child: Text('Nothing to show'))
          : _imageBuilding && _receiptPngBytes == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_receiptPngBytes != null)
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _receiptPngBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  )
                else
                  SelectableText(
                    _buildReceiptText(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _download,
                  child: const Text('Download receipt'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _share,
                  child: const Text('Share receipt'),
                ),
              ],
            ),
            ),
    );
  }
}
