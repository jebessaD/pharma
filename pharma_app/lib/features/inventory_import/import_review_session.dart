import 'import_models.dart';

/// Optional metadata when the extraction came from a spreadsheet (for undo).
class SpreadsheetImportMeta {
  const SpreadsheetImportMeta({
    required this.sourceKind,
    required this.filename,
    this.sheetName,
  });

  final String sourceKind;
  final String filename;
  final String? sheetName;
}

/// Holds extraction output between capture and review routes (go_router).
class ImportReviewSession {
  const ImportReviewSession({
    required this.mode,
    required this.extraction,
    required this.teamId,
    required this.branchId,
    this.spreadsheetMeta,
  });

  final ImportMode mode;
  final ExtractionResult extraction;
  final String teamId;
  final String branchId;
  final SpreadsheetImportMeta? spreadsheetMeta;
}

ImportReviewSession? importReviewSession;

void setImportReviewSession(ImportReviewSession session) {
  importReviewSession = session;
}

ImportReviewSession? takeImportReviewSession() {
  final session = importReviewSession;
  importReviewSession = null;
  return session;
}
