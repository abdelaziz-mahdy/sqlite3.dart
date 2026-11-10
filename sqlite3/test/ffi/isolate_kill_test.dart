@Tags(['ffi'])
library;

import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  // Regression test for https://github.com/simolus3/sqlite3.dart/issues/437
  test('killing an isolate while it closes statements', () async {
    final random = Random();
    for (var i = 0; i < 300; i++) {
      final ready = ReceivePort();
      final exit = ReceivePort();
      final isolate = await Isolate.spawn(
        _prepareAndCloseForever,
        ready.sendPort,
        onExit: exit.sendPort,
      );
      await ready.first;
      await Future<void>.delayed(Duration(microseconds: random.nextInt(2000)));
      isolate.kill(priority: Isolate.immediate);
      await exit.first;
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

void _prepareAndCloseForever(SendPort ready) {
  final db = sqlite3.openInMemory();
  // Prepare and close one statement before the kill can arrive, so that the
  // isolate registers the statement finalizer up front. Killing an isolate
  // while it registers a finalizer can crash the VM during isolate shutdown
  // (https://dart-review.googlesource.com/c/sdk/+/TBD), which is a different
  // bug from the one tested here.
  db.prepare('SELECT 1').close();
  ready.send(null);
  for (var i = 0; ; i++) {
    final stmt = db.prepare('SELECT ?');
    stmt.select([i]);
    stmt.close();
  }
}
