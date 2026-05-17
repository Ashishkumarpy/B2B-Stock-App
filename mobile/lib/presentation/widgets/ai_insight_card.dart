import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AiInsightCard extends StatelessWidget {
  final String insight;
  final int index;

  const AiInsightCard({
    super.key,
    required this.insight,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isAlert = insight.contains('⚠️') || insight.contains('📉') || insight.contains('🔥');
    final color = isAlert ? AppTheme.danger : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.sp12),
      padding: const EdgeInsets.all(AppTheme.sp16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.sp8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAlert ? Icons.auto_awesome_rounded : Icons.lightbulb_outline_rounded,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: AppTheme.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.contains(':') ? insight.split(':')[0] : 'Insight #${index + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.contains(':') ? insight.split(':')[1].trim() : insight,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.isDarkMode(context) ? Colors.white70 : Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
