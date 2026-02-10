class CategorizationProgress {
  const CategorizationProgress({
    required this.processedQuestions,
    required this.totalQuestions,
    required this.batchIndex,
    required this.totalBatches,
    required this.stage,
    this.stageProgress,
    this.currentBatchSize,
  });

  final int processedQuestions;
  final int totalQuestions;
  final int batchIndex;
  final int totalBatches;
  final String stage;
  final double? stageProgress;
  final int? currentBatchSize;
}

typedef CategorizationProgressCallback =
    void Function(CategorizationProgress progress);
