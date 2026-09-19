// Development-only host for OS notification tap/lifecycle verification.
import 'package:flutter/material.dart';
import 'package:muscle_memory/main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('MUSCLEMORY 通知確認')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                key: const Key('scheduleProbe'),
                onPressed: () => RestNotificationService.schedule(8),
                child: const Text('8秒後に通知'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: RestNotificationService.cancel,
                child: const Text('キャンセル'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: RestNotificationService.playCompletionFeedback,
                child: const Text('終了音確認'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
