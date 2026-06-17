import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction.dart';

class TransactionActivityCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;
  final Widget? actionMenu;
  final EdgeInsetsGeometry margin;

  const TransactionActivityCard({
    super.key,
    required this.transaction,
    this.onTap,
    this.actionMenu,
    this.margin = const EdgeInsets.only(bottom: AppTheme.sp8),
  });

  static String extractCustomerName(String? notes) {
    if (notes == null || notes.trim().isEmpty) return '';
    final match =
        RegExp(r'Customer:\s*([^|]+)', caseSensitive: false).firstMatch(notes);
    return match?.group(1)?.trim() ?? '';
  }

  static ({int cartons, int pcsPerCarton})? parseCartonFromNotes(
      String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    final match = RegExp(
      r'(\d+)\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(notes);
    if (match == null) return null;
    final cartons = int.tryParse(match.group(1) ?? '');
    final pcsPerCarton = int.tryParse(match.group(2) ?? '');
    if (cartons == null || pcsPerCarton == null || pcsPerCarton <= 0) {
      return null;
    }
    return (cartons: cartons, pcsPerCarton: pcsPerCarton);
  }

  static String cleanNotes(String? notes) {
    if (notes == null) return '';
    var clean = notes.trim();
    clean = clean
        .replaceFirst(
          RegExp(r'^Customer:\s*[^|]+(\|)?', caseSensitive: false),
          '',
        )
        .trim();
    clean = clean
        .replaceFirst(
          RegExp(
            r'^\d+\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*\d+\s*(?:pcs)?\s*(\|)?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    clean = clean.replaceFirst(RegExp(r'^\|\s*'), '').trim();
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    final isIn = transaction.isStockIn;
    final isShift = transaction.isShift;
    final actionColor = isShift
        ? const Color(0xFF2563EB)
        : (isIn ? AppTheme.success : const Color(0xFFFF3F8E));
    final actionSoft = isShift
        ? const Color(0xFFEAF1FF)
        : (isIn ? AppTheme.successLight : const Color(0xFFFFEDF5));
    final productCode = transaction.productCode.isNotEmpty
        ? transaction.productCode
        : 'No Code';
    final productName = transaction.productName.isNotEmpty
        ? transaction.productName
        : 'Unknown Product';
    final workerName = transaction.workerName.isNotEmpty
        ? transaction.workerName
        : 'Unknown Worker';
    final customerName = extractCustomerName(transaction.notes);
    final notes = cleanNotes(transaction.notes);
    final warehouseName = (transaction.warehouseName ?? '').trim().isEmpty
        ? 'Warehouse'
        : transaction.warehouseName!.trim();
    final colorName = transaction.colorName?.trim() ?? '';
    final parsedCarton = parseCartonFromNotes(transaction.notes);
    final cartons = transaction.cartons ?? parsedCarton?.cartons;
    final pcsPerCarton = transaction.pcsPerCarton ?? parsedCarton?.pcsPerCarton;
    final showCartons = cartons != null && cartons > 0;
    // Carton text shown on the lower line, for example: "3 ctn (150 pcs)".
    final cartonLabel =
        showCartons ? '$cartons ctn (${transaction.quantity} pcs)' : '';
    final qtyDetailed =
        AppFormatters.formatQuantity(transaction.quantity, pcsPerCarton);
    final dateLabel =
        DateFormat('dd MMM, hh:mm a').format(transaction.createdAt);
    final refLabel = transaction.id.length >= 3
        ? '#${transaction.id.substring(0, 3).toUpperCase()}'
        : '#${transaction.id.toUpperCase()}';

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      actionColor,
                      const Color(0xFFC85CFF),
                    ],
                  ),
                ),
              ),
              Padding(
                // Main card padding. Increase these values if the card feels clustered.
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: actionColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isShift
                                ? LucideIcons.arrowLeftRight
                                : (isIn
                                    ? LucideIcons.arrowUp
                                    : LucideIcons.arrowDown),
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          color: AppTheme.textPrimary.withValues(alpha: 0.12),
                          child: Text(
                            refLabel,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Padding(
                            // Keeps the text from sitting under the bottom-right edit menu.
                            padding: EdgeInsets.only(
                              right: actionMenu == null ? 0 : 15,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            productCode,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.primaryTextColor(
                                                  context),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color:
                                                  AppTheme.secondaryTextColor(
                                                      context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      constraints:
                                          const BoxConstraints(minWidth: 50),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: actionSoft,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${isShift ? '' : (isIn ? '+' : '-')}${transaction.quantity}',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: actionColor,
                                              height: 1,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            'pcs',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: actionColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  // Worker/customer pill spacing.
                                  spacing: 8,
                                  runSpacing: 5,
                                  children: [
                                    _ActivityPill(
                                      icon: LucideIcons.userCircle,
                                      text: workerName,
                                      foreground: const Color(0xFF6D28D9),
                                      background: const Color(0xFFF5F0FF),
                                      border: const Color(0xFFE9D5FF),
                                    ),
                                    if (customerName.isNotEmpty)
                                      _ActivityPill(
                                        icon: LucideIcons.userCheck,
                                        text: customerName,
                                        foreground: const Color(0xFF0369A1),
                                        background: const Color(0xFFEFF8FF),
                                        border: const Color(0xFFBAE6FD),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  // Color, warehouse, and date spacing.
                                  spacing: 14,
                                  runSpacing: 5,
                                  children: [
                                    if (colorName.isNotEmpty)
                                      _MutedMeta(
                                        icon: LucideIcons.palette,
                                        text: colorName,
                                      ),
                                    _MutedMeta(
                                      icon: LucideIcons.warehouse,
                                      text: warehouseName,
                                    ),
                                    _MutedMeta(
                                      icon: LucideIcons.clock,
                                      text: dateLabel,
                                    ),
                                  ],
                                ),
                                // Space between metadata and carton/quantity line.
                                const SizedBox(height: 7.5),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showCartons) ...[
                                      _CartonMark(color: actionColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        cartonLabel,
                                        style: TextStyle(
                                          color: actionColor,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                      ),
                                    ] else
                                      Text(
                                        qtyDetailed,
                                        style: TextStyle(
                                          color: AppTheme.secondaryTextColor(
                                              context),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          height: 1,
                                        ),
                                      ),
                                  ],
                                ),
                                if (notes.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    notes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          AppTheme.secondaryTextColor(context),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (actionMenu != null)
                            Positioned(
                              // Floats the edit menu so its 48px tap area does not stretch the quantity row.
                              right: -7,
                              bottom: -7,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: OverflowBox(
                                  maxWidth: 48,
                                  maxHeight: 48,
                                  alignment: Alignment.center,
                                  child: actionMenu!,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color foreground;
  final Color background;
  final Color border;

  const _ActivityPill({
    required this.icon,
    required this.text,
    required this.foreground,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartonMark extends StatelessWidget {
  final Color color;

  const _CartonMark({required this.color});

  @override
  Widget build(BuildContext context) {
    // Custom carton mark avoids missing icon-font glyphs on some devices.
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color, width: 1.3),
      ),
      child: Center(
        child: Container(
          width: 1.2,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _MutedMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MutedMeta({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.mutedTextColor(context)),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.secondaryTextColor(context),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
