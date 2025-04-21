// single producer muti comsume

import 'dart:async';
import 'dart:collection'; // Import Queue

/// A simple Single-Producer, Multi-Consumer (SPMC) queue.
///
/// Allows one producer to [send] tasks and multiple consumers to
/// asynchronously [waitTask] for available tasks.
class SpmcChannel<T> {
  // Use Queues for efficient O(1) add/remove at ends
  final _workers = Queue<
      Completer<T>>(); // Queue of waiting consumers (represented by Completers)
  final _tasks = Queue<T>(); // Queue of pending tasks

  /// Waits for a task to become available.
  ///
  /// If tasks are already available in the queue, returns the next one immediately
  /// (wrapped in a Future).
  /// Otherwise, registers the caller as a waiting worker and returns a Future
  /// that will complete when a task is sent via [send].
  Future<T> waitTask() {
    // Check if a task is immediately available
    if (_tasks.isNotEmpty) {
      // Return it directly, wrapped in a Future for consistent return type
      // Using Future.value ensures it's still async if the caller awaits it.
      return Future.value(_tasks.removeFirst());
    } else {
      // No tasks available, create a Completer to represent the wait
      final completer = Completer<T>();
      _workers.add(completer);
      // Return the Future associated with the Completer
      return completer.future;
    }
  }

  /// Sends a task.
  ///
  /// If any workers are waiting ([waitTask] has been called and is awaiting),
  /// the task is immediately delivered to the longest-waiting worker.
  /// Otherwise, the task is added to the internal queue for a future worker.
  void send(T value) {
    // Check if any worker is waiting
    if (_workers.isNotEmpty) {
      // A worker is waiting, get its Completer (FIFO)
      final completer = _workers.removeFirst();

      // Complete the worker's Future with the value.
      // Use Future.microtask to ensure the completion happens asynchronously
      // in the next microtask loop. This prevents potential synchronous
      // execution of the completer's listeners within the send() call,
      // leading to more predictable async behavior.
      Future.microtask(() => completer.complete(value));
    } else {
      // No workers waiting, add the task to the queue
      _tasks.add(value); // add() is equivalent to addLast() for Queue
    }
  }

  // --- Optional utility methods ---

  /// Returns `true` if there are tasks waiting to be processed.
  bool get hasPendingTasks => _tasks.isNotEmpty;

  /// Returns the number of workers currently waiting for a task.
  int get waitingWorkerCount => _workers.length;

  /// Clears all pending tasks and notifies any waiting workers with an error.
  /// This can be used to shut down the queue.
  void dispose([dynamic error, StackTrace? stackTrace]) {
    final errorToSignal = error ?? SpmcDisposedException();
    // Notify all waiting workers
    while (_workers.isNotEmpty) {
      final completer = _workers.removeFirst();
      // Ensure completion happens async
      Future.microtask(
        () => completer.completeError(errorToSignal, stackTrace),
      );
    }
    // Clear any tasks that were never picked up
    _tasks.clear();
  }
}

/// Exception thrown when trying to use a disposed Spmc queue or when
/// a waiting worker is notified during disposal.
class SpmcDisposedException implements Exception {
  final String message;
  SpmcDisposedException([this.message = "Spmc queue was disposed."]);
  @override
  String toString() => message;
}
