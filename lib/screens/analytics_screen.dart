import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final stats = appState.userStats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _StatItem(
                  title: 'Всего ответов',
                  value: '${stats['total_answers'] ?? 0}',
                ),
                _StatItem(
                  title: 'Точность',
                  value:
                      '${((stats['accuracy_pct'] ?? 0) as num).toStringAsFixed(1)}%',
                ),
                _StatItem(
                  title: 'Streak',
                  value: '${stats['streak'] ?? 0}',
                ),
                _StatItem(
                  title: 'Среднее время',
                  value:
                      '${((stats['avg_time_seconds'] ?? 0) as num).toStringAsFixed(1)} сек',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, Object?>>>(
          future: appState.categoryStats(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (rows.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Недостаточно данных для графиков.'),
                ),
              );
            }

            return Column(
              children: <Widget>[
                _CategoryPieChart(rows: rows),
                const SizedBox(height: 8),
                _CategoryAccuracyBarChart(rows: rows),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, Object?>>>(
          future: appState.progressByDay(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            return _ProgressLineChart(rows: rows);
          },
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
        ],
      ),
    );
  }
}

class _CategoryPieChart extends StatelessWidget {
  const _CategoryPieChart({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      const Color(0xFFFF6B6B),
      const Color(0xFF7AD3FF),
      const Color(0xFF95E1A3),
      const Color(0xFFFFD166),
      const Color(0xFFC3AED6),
      const Color(0xFF84DCC6),
      const Color(0xFFF28482),
    ];

    final sections = rows.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      final value = (row['total_questions'] as num?)?.toDouble() ?? 0;
      final label = row['category']?.toString() ?? 'Без категории';
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: value,
        title: value > 0 ? label : '',
        radius: 90,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
    }).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Распределение вопросов по категориям',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 30,
                  sectionsSpace: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryAccuracyBarChart extends StatelessWidget {
  const _CategoryAccuracyBarChart({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final barRows = rows.take(8).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Точность по категориям (%)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= barRows.length) {
                            return const SizedBox.shrink();
                          }
                          final category = barRows[idx]['category']
                                  ?.toString()
                                  .replaceAll(' ', '\n') ??
                              '—';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              category,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: barRows.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    final value = (row['accuracy_pct'] as num?)?.toDouble() ?? 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: value,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                          color: const Color(0xFF7AD3FF),
                        ),
                      ],
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLineChart extends StatelessWidget {
  const _ProgressLineChart({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Данных о прогрессе по дням пока нет.'),
        ),
      );
    }

    final points = rows.asMap().entries.map((entry) {
      final idx = entry.key.toDouble();
      final row = entry.value;
      final accuracy = (row['accuracy_pct'] as num?)?.toDouble() ?? 0;
      return FlSpot(idx, accuracy);
    }).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Прогресс по дням',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: rows.length < 8 ? 1 : (rows.length / 6).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= rows.length) {
                            return const SizedBox.shrink();
                          }
                          final day = rows[idx]['day']?.toString() ?? '';
                          DateTime? parsed;
                          if (day.isNotEmpty) {
                            parsed = DateTime.tryParse(day);
                          }
                          final label = parsed == null
                              ? day
                              : DateFormat('dd.MM').format(parsed);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(label, style: const TextStyle(fontSize: 9)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: <LineChartBarData>[
                    LineChartBarData(
                      spots: points,
                      isCurved: true,
                      color: const Color(0xFFFF6B6B),
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
