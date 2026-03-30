import 'package:flutter/material.dart';

/// Счётчики мест по статусам — для правого верхнего угла карты (как в макете).
class CemeteryPlotStatsLegend extends StatelessWidget {
  final int freeCount;
  final int reservedCount;
  final int occupiedCount;

  const CemeteryPlotStatsLegend({
    super.key,
    required this.freeCount,
    required this.reservedCount,
    required this.occupiedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 6,
        children: [
          _StatChip(color: Colors.green, label: 'Свободно', count: freeCount),
          _StatChip(
            color: Colors.grey.shade600,
            label: 'Захоронено',
            count: occupiedCount,
          ),
          _StatChip(color: Colors.orange, label: 'Бронь', count: reservedCount),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _StatChip({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF433A3F),
            ),
          ),
        ],
      ),
    );
  }
}

class GraveStatusLegend extends StatelessWidget {
  const GraveStatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegendItem(color: Colors.green, label: 'Свободно'),
          const SizedBox(height: 4),
          _LegendItem(color: Colors.orange, label: 'Забронировано'),
          const SizedBox(height: 4),
          _LegendItem(color: Colors.grey.shade600, label: 'Захоронено'),
          const SizedBox(height: 4),
          _LegendItem(color: Colors.blue.shade400, label: 'Резерв'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.7),
            border: Border.all(color: Colors.black54, width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF433A3F)),
        ),
      ],
    );
  }
}
