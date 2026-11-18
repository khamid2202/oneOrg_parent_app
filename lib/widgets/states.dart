import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import 'theme.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.padding = 40});
  final double padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: padding),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: context.c.muted),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(
          children: [
            Icon(icon, size: 30, color: context.c.muted.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.c.muted, fontSize: 14)),
          ],
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 30, color: Color(0xFFF43F5E)),
            const SizedBox(height: 8),
            Text(context.t(errorKey(error)),
                textAlign: TextAlign.center, style: TextStyle(color: context.c.muted, fontSize: 14)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: onRetry,
                child: Text(context.t('common.retry')),
              ),
            ],
          ],
        ),
      );
}
