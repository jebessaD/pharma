import 'package:flutter/material.dart';

import '../medicine_catalog/medicine_catalog.dart';

class MedicineCatalogAutocompleteField extends StatefulWidget {
  const MedicineCatalogAutocompleteField({
    super.key,
    required this.controller,
    required this.catalog,
    required this.label,
    required this.onSelected,
    this.validator,
    this.hintText = 'Search by medicine or generic name',
    this.displayTextForOption,
  });

  final TextEditingController controller;
  final List<MedicineCatalogEntry> catalog;
  final String label;
  final ValueChanged<MedicineCatalogEntry> onSelected;
  final String? Function(String?)? validator;
  final String hintText;
  final String Function(MedicineCatalogEntry entry)? displayTextForOption;

  @override
  State<MedicineCatalogAutocompleteField> createState() =>
      _MedicineCatalogAutocompleteFieldState();
}

class _MedicineCatalogAutocompleteFieldState
    extends State<MedicineCatalogAutocompleteField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<MedicineCatalogEntry>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (entry) =>
          widget.displayTextForOption?.call(entry) ??
          (entry.genericName ?? entry.name),
      optionsBuilder: (value) =>
          searchMedicineCatalog(widget.catalog, value.text),
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
          ),
          validator: widget.validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList(growable: false);
        final cs = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 340),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: cs.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final primary = entry.genericName ?? entry.name;
                  final brand = entry.genericName != null &&
                          entry.genericName!.isNotEmpty &&
                          entry.name.isNotEmpty
                      ? entry.name
                      : null;
                  final details = [
                    if (brand != null) brand,
                    entry.strength,
                    entry.dosageForm,
                    entry.presentation,
                    entry.subcategory,
                  ].where((value) => value != null && value.isNotEmpty);
                  return ListTile(
                    dense: true,
                    title: Text(primary),
                    subtitle: details.isEmpty
                        ? null
                        : Text(
                            details.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => onSelected(entry),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class MedicineOptionalDetailsSection extends StatefulWidget {
  const MedicineOptionalDetailsSection({
    super.key,
    required this.subcategory,
    required this.country,
    required this.presentation,
    required this.strength,
    required this.dosageForm,
  });

  final TextEditingController subcategory;
  final TextEditingController country;
  final TextEditingController presentation;
  final TextEditingController strength;
  final TextEditingController dosageForm;

  @override
  State<MedicineOptionalDetailsSection> createState() =>
      _MedicineOptionalDetailsSectionState();
}

class _MedicineOptionalDetailsSectionState
    extends State<MedicineOptionalDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(_expanded ? 'Hide more details' : 'Add more details'),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.subcategory,
            decoration: const InputDecoration(
              labelText: 'Subcategory (optional)',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: widget.country,
            decoration: const InputDecoration(labelText: 'Country (optional)'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: widget.presentation,
            decoration: const InputDecoration(
              labelText: 'Presentation (optional)',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: widget.strength,
            decoration: const InputDecoration(labelText: 'Strength (optional)'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: widget.dosageForm,
            decoration: const InputDecoration(
              labelText: 'Dosage form (optional)',
            ),
          ),
        ],
      ],
    );
  }
}

void applyMedicineCatalogEntry({
  required MedicineCatalogEntry entry,
  required TextEditingController name,
  required TextEditingController genericName,
  required TextEditingController subcategory,
  required TextEditingController country,
  required TextEditingController presentation,
  required TextEditingController strength,
  required TextEditingController dosageForm,
}) {
  name.text = entry.name;
  genericName.text = entry.genericName ?? '';
  subcategory.text = entry.subcategory ?? '';
  country.clear();
  presentation.text = entry.presentation ?? '';
  strength.text = entry.strength ?? '';
  dosageForm.text = entry.dosageForm ?? '';
}

String? optionalMedicineText(TextEditingController controller) {
  final text = controller.text.trim();
  return text.isEmpty ? null : text;
}
