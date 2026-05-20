import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/product.dart';


class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final perCarton =
        (product.pcsPerCarton != null && product.pcsPerCarton! > 0)
            ? product.pcsPerCarton!
            : 1;
    final cartons = product.quantity ~/ perCarton;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      color: Theme.of(context).cardColor,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrl != null && product.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[100],
                            child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey),
                          ),
                        )
                      : Container(
                          color: Colors.grey[100],
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Colors.grey, size: 32),
                        ),
                  if (product.stockStatus != StockStatus.inStock)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: product.stockStatus == StockStatus.outOfStock
                              ? AppTheme.danger
                              : AppTheme.warning,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSM),
                        ),
                        child: Text(
                          product.stockStatus == StockStatus.outOfStock
                              ? 'OUT'
                              : 'LOW',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  if (onEdit != null || onDelete != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            cardColor: Theme.of(context).canvasColor,
                          ),
                          child: PopupMenuButton<String>(
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            onSelected: (value) {
                              if (value == 'edit' && onEdit != null) {
                                onEdit!();
                              } else if (value == 'delete' && onDelete != null) {
                                onDelete!();
                              }
                            },
                            itemBuilder: (context) => [
                              if (onEdit != null)
                                PopupMenuItem(
                                  value: 'edit',
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded, size: 16, color: Theme.of(context).textTheme.bodyMedium?.color),
                                      const SizedBox(width: 8),
                                      const Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              if (onDelete != null)
                                const PopupMenuItem(
                                  value: 'delete',
                                  height: 36,
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                                      SizedBox(width: 8),
                                      Text('Delete', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.danger)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.sp8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${product.quantity} pcs',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: product.quantity <= product.threshold
                                    ? AppTheme.danger
                                    : AppTheme.success,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              '$cartons ctn${perCarton > 1 ? ' • $perCarton/ctn' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₹${product.price % 1 == 0 ? product.price.toInt() : product.price}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
