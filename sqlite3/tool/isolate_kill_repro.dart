// Fork-only experiment: kill an isolate many times while it runs one of
// several workloads, to find which one crashes the VM on Windows.
//
//   dart run tool/isolate_kill_repro.dart <variant> <kills>
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';

final _freeFinalizer = NativeFinalizer(malloc.nativeFree);

final class _Owned implements Finalizable {
  final Pointer<Uint8> ptr = malloc<Uint8>(64);
  _Owned() {
    _freeFinalizer.attach(this, ptr.cast(), detach: this);
  }
  void free() {
    _freeFinalizer.detach(this);
    malloc.free(ptr);
  }
}

void _pure(SendPort ready) {
  ready.send(null);
  var list = <Object>[];
  for (var i = 0;; i++) {
    list.add([i, '$i']);
    if (list.length > 1000) list = <Object>[];
  }
}

void _ffiFinalizer(SendPort ready) {
  ready.send(null);
  for (;;) {
    _Owned().free();
  }
}

void _exec(SendPort ready) {
  final db = sqlite3.openInMemory();
  ready.send(null);
  for (;;) {
    db.execute('SELECT 1');
  }
}

void _prepClose(SendPort ready) {
  final db = sqlite3.openInMemory();
  ready.send(null);
  for (var i = 0;; i++) {
    final stmt = db.prepare('SELECT ?');
    stmt.select([i]);
    stmt.close();
  }
}

void _prepLeak(SendPort ready) {
  final db = sqlite3.openInMemory();
  ready.send(null);
  for (var i = 0;; i++) {
    db.prepare('SELECT ?').select([i]);
  }
}

void _dbCycle(SendPort ready) {
  ready.send(null);
  for (;;) {
    sqlite3.openInMemory().close();
  }
}

const _variants = <String, void Function(SendPort)>{
  'pure': _pure,
  'ffi_finalizer': _ffiFinalizer,
  'exec': _exec,
  'prepclose': _prepClose,
  'prepleak': _prepLeak,
  'dbcycle': _dbCycle,
};

Future<void> main(List<String> args) async {
  final body = _variants[args[0]]!;
  final kills = int.parse(args[1]);
  final random = Random();
  for (var i = 0; i < kills; i++) {
    final ready = ReceivePort();
    final exit = ReceivePort();
    final isolate =
        await Isolate.spawn(body, ready.sendPort, onExit: exit.sendPort);
    await ready.first;
    await Future<void>.delayed(Duration(microseconds: random.nextInt(2000)));
    isolate.kill(priority: Isolate.immediate);
    await exit.first;
  }
  print('${args[0]}: $kills kills, no crash');
}
