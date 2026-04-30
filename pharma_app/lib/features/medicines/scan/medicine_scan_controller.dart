import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> showCameraScanSheet(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CameraScanSheet(),
  );
}

class _CameraScanSheet extends StatefulWidget {
  const _CameraScanSheet();

  @override
  State<_CameraScanSheet> createState() => _CameraScanSheetState();
}

class _CameraScanSheetState extends State<_CameraScanSheet> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade500,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Scan medicine barcode'),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                onDetect: (capture) {
                  if (_handled) return;
                  final code = capture.barcodes.firstOrNull?.rawValue?.trim();
                  if (code == null || code.isEmpty) return;
                  _handled = true;
                  Navigator.of(context).pop(code);
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Align barcode in the camera frame'),
          ),
        ],
      ),
    );
  }
}
