import 'package:flutter/material.dart';
import 'dart:isolate';
import 'dart:async';
import 'dart:io';
import 'utils.dart';

class TransferProgress {
  final int totalBytes;
  final int currentBytes;
  final String message;

  TransferProgress({
    required this.totalBytes,
    required this.currentBytes,
    required this.message,
  });

  @override
  String toString() {
    return 'TransferProgress(currentBytes: $currentBytes, totalBytes: $totalBytes, message: "$message")';
  }
}

class LoadingIndicator2 extends StatelessWidget {
  final Stream<TransferProgress> progressStream;

  const LoadingIndicator2({super.key, required this.progressStream});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StreamBuilder<TransferProgress>(
        stream: progressStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final progress = snapshot.data!;
          final currentBytes = progress.currentBytes;
          final totalBytes = progress.totalBytes;
          final message = progress.message;

          double progressValue = (totalBytes > 0)
              ? currentBytes / totalBytes
              : 1.0;

          var percentage = (progressValue * 100).toStringAsFixed(1);

          bool isProgressKnown = totalBytes > 0;

          return Center(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min, // make the column occupy the minimum space
              crossAxisAlignment:
                  CrossAxisAlignment.center, // center align the content
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                SizedBox(
                  width: 200.0,
                  child: LinearProgressIndicator(
                    value: isProgressKnown ? progressValue : null,
                  ),
                ),
                SizedBox(height: 10),

                SizedBox(
                  width: 200.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatBytes(totalBytes),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 5),

                // 4. Downloading xxxx
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LoadingIndicator extends StatelessWidget {
  final Stream<TransferProgress> progressStream;

  const LoadingIndicator({super.key, required this.progressStream});

  @override
  Widget build(BuildContext context) {
    double lastProgressValue = 0;
    bool? firstStreamElement;
    // bool enableProgress = false;
    // DateTime? transferStartTime;
    return Center(
      child: StreamBuilder<TransferProgress>(
        stream: progressStream,
        builder: (context, snapshot) {
          // --- Handle initial state or error ---
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // Show a simple circular indicator while waiting for the first data point
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          if (firstStreamElement == null) {
            firstStreamElement = true;
          } else {
            firstStreamElement = false;
          }

          // --- Data received, build progress UI ---
          final progress = snapshot.data!;
          final currentBytes = progress.currentBytes;
          final totalBytes = progress.totalBytes;
          final message = progress.message;

          // Determine if total bytes are known (to show determinate progress)
          bool isProgressKnown = totalBytes > 0;

          // Calculate the *target* progress value (between 0.0 and 1.0)
          // This is the value the animation should reach when it finishes.
          // If total is unknown, the target is conceptually 0 or not used for the determinate bar.
          double targetProgressValue = isProgressKnown
              ? currentBytes / totalBytes
              : 0.0;
          if (targetProgressValue >= 1.0) {
            targetProgressValue = 0.999;
          }

          // print('targetProgressValue2: $targetProgressValue');

          var tweenAnimationDuration = Duration(
            milliseconds: ProgressLimiter.getIntervalMs(totalBytes),
          );
          var difference = targetProgressValue - lastProgressValue;
          // If the difference is large, increase the animation duration for a smoother transition.
          if (difference > 0.2 &&
              totalBytes > ProgressLimiter.minLimitTransferBytes) {
            const baseP20Duration = 200;
            tweenAnimationDuration = Duration(
              milliseconds: ((difference / 0.2) * baseP20Duration).toInt(),
            );
          }
          if (difference > 0.5 &&
              totalBytes < ProgressLimiter.minLimitTransferBytes) {
            tweenAnimationDuration = Duration(milliseconds: 200);
          }
          // print(
          //     'tweenAnimationDuration: ${tweenAnimationDuration.inMilliseconds}, difference: $difference, targetProgressValue: $targetProgressValue, lastProgressValue: $lastProgressValue');

          lastProgressValue = targetProgressValue;

          // Use TweenAnimationBuilder to animate the progress value smoothly
          // The tween animates from the last 'end' value to the new 'targetProgressValue'.
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: firstStreamElement == true ? 0.0 : null,
              end: targetProgressValue,
            ),
            // The duration over which the animation should occur.
            // This should ideally match the stream's update interval for smoothness.
            // duration: Duration(milliseconds: streamIntervalMs),
            duration: tweenAnimationDuration,
            // Use a linear curve for consistent speed animation
            curve: Curves.linear,
            // This builder is called every frame during the animation.
            builder: (context, animatedProgressValue, child) {
              // animatedProgressValue is the current value between the start and end of the tween.

              // Calculate the percentage using the animated value for smooth text update
              double animatedPercentage = animatedProgressValue * 100;
              // print(
              //     'animatedPercentage: $animatedPercentage, animatedProgressValue: $animatedProgressValue, targetProgressValue: $targetProgressValue');

              return Column(
                mainAxisSize: MainAxisSize
                    .min, // make the column occupy the minimum space
                crossAxisAlignment:
                    CrossAxisAlignment.center, // center align the content
                children: [
                  // Optionally keep a CircularProgressIndicator for general activity,
                  // or remove it if the linear one is sufficient.
                  CircularProgressIndicator(),
                  SizedBox(height: 20), // Adjust spacing if circular removed

                  SizedBox(
                    width: 200.0, // Fixed width for the linear indicator
                    child: LinearProgressIndicator(
                      // Use the animated value if progress is known, otherwise indeterminate
                      value: isProgressKnown ? animatedProgressValue : null,
                      // Add a background color when indeterminate to make it visible
                      backgroundColor: isProgressKnown
                          ? null
                          : Theme.of(
                              context,
                            ).colorScheme.primary.withAlpha((0.2 * 255) as int),
                    ),
                  ),
                  SizedBox(height: 10),

                  SizedBox(
                    width: 200.0, // Fixed width for the row
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Show total bytes (this updates instantly with new data)
                        Text(
                          formatBytes(totalBytes),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        // Show percentage using the animated value
                        Text(
                          isProgressKnown
                              ? '${animatedPercentage.toStringAsFixed(1)}%'
                              // If progress is unknown, show ellipsis or current bytes / unknown
                              : '${formatBytes(currentBytes)} / ...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 5),

                  // 4. Downloading xxxx (uncommented as it provides context)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// T can't be nullable type, e.g. int? or double?
class ProgressLimiter<T> {
  /// The minimum time interval in milliseconds between sending updates.
  late final int intervalMs;

  /// The SendPort to which progress updates will be sent.
  final SendPort sendPort;

  /// A function to determine if two progress values should be considered the same.
  /// Returns true if they are the same, false otherwise.
  final bool Function(T oldValue, T newValue) isSame;

  /// The last progress value that was successfully sent.
  T? lastSent;

  /// The latest progress value received, waiting to be potentially sent.
  T? _pendingProgress;

  /// The timer used to schedule the next send operation.
  Timer? _timer;

  /// The cooldown time has passed
  bool _cooldownComplete = false;

  /// The minimum transfer bytes to start the limit
  static const int minLimitTransferBytes = 1024 * 1024 * 10;

  ProgressLimiter({
    required this.sendPort,
    required this.isSame,
    required int totalBytes,
  }) {
    intervalMs = getIntervalMs(totalBytes);
  }

  static int getIntervalMs(int totalBytes) {
    if (totalBytes < minLimitTransferBytes) {
      return 30; // Minimum limit to prevent performance issues when transferring a large number of small files
    }
    if (Platform.isIOS || Platform.isAndroid) {
      return 200;
    } else {
      return 80;
    }
    // return 200;
  }

  void _refreshTimer() {
    _cooldownComplete = false;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: intervalMs), _timerSendNow);
  }

  void update(T progress) {
    if (_cooldownComplete) {
      if (isSame(lastSent as T, progress)) {
        return;
      }
      lastSent = progress;
      _pendingProgress = null;
      sendPort.send(progress);
      _refreshTimer();
      return;
    }

    // first time
    if (lastSent == null) {
      lastSent = progress;
      sendPort.send(progress);
      _refreshTimer();
      return;
    }

    _pendingProgress = progress;
  }

  void _timerSendNow() {
    if (_pendingProgress == null) {
      _cooldownComplete = true;
      return;
    }
    if (isSame(lastSent as T, _pendingProgress as T)) {
      _cooldownComplete = true;
      return;
    }

    lastSent = _pendingProgress;
    sendPort.send(_pendingProgress as T);
    _pendingProgress = null;
    _refreshTimer();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pendingProgress = null;
    _cooldownComplete = false;
  }
}
