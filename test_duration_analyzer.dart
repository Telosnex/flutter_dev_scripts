// ignore_for_file: avoid_print, prefer-declaring-const-constructor

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// Configuration class for customizable thresholds and options
class AnalyzerConfig {
  final int slowTestThreshold;
  final bool useColors;
  final bool showStatistics;
  final bool showGroups;

  AnalyzerConfig({
    this.slowTestThreshold = 500,
    this.useColors = true,
    this.showStatistics = true,
    this.showGroups = true,
  });
}

class TestStatistics {
  final double mean;
  final double median;
  final double standardDev;
  final int totalDuration;
  final int slowestTest;
  final int fastestTest;

  TestStatistics({
    required this.mean,
    required this.median,
    required this.standardDev,
    required this.totalDuration,
    required this.slowestTest,
    required this.fastestTest,
  });
}

// Data structures
final Map<int, TestInfo> tests = {};
final Map<String, int> testDurations = {};

void main(List<String> args) {
  if (args.isEmpty) {
    print(
        'Usage: dart test_duration_analyzer.dart <path_to_test_log.json> [options]');
    print('Options:');
    print(
        '  --threshold=<ms>    Mark tests slower than this threshold (default: 500ms)');
    print('  --no-color         Disable colored output');
    print('  --no-stats         Disable statistics');
    print('  --no-groups        Disable group-based analysis');
    exit(1);
  }

  final config = parseArgs(args);
  final filePath = args[0];
  final file = File(filePath);

  if (!file.existsSync()) {
    print('Error: File not found: $filePath');
    exit(1);
  }

  // Process file
  try {
    file.readAsLinesSync().forEach((line) {
      if (line.isEmpty) return;

      try {
        if (line.startsWith('[')) return;

        final Map<String, dynamic> event = json.decode(line);

        if (event['type'] == 'testStart') {
          final testId = event['test']['id'] as int;
          final testName = event['test']['name'];

          // Skip loading events
          if (testName.startsWith('loading ')) {
            return;
          }

          final startTime = event['time'];
          tests[testId] = TestInfo(
            name: testName,
            startTime: startTime,
            groups: event['test']['groupIDs'] != null
                ? List<String>.from(
                    event['test']['groupIDs'].map((id) => id.toString()))
                : const [],
          );
        }

        if (event['type'] == 'testDone') {
          final testId = event['testID'] as int;

          if (tests.containsKey(testId)) {
            final endTime = event['time'] as int;
            final testInfo = tests[testId]!;
            final duration = endTime - testInfo.startTime;
            testDurations[testInfo.name] = duration;
          }
        }
        // rationale: printing every non-json line overflows terminal
        // ignore: empty_catches
      } catch (e) {

      }
    });
  } catch (e) {
    print('Error reading file: $e');
    exit(1);
  }

  if (testDurations.isEmpty) {
    print('No test data found in the file.');
    exit(1);
  }

  // Calculate statistics
  final stats = calculateStatistics(testDurations.values.toList());

  // Print results
  printResults(testDurations, stats, config);
}

TestStatistics calculateStatistics(List<int> durations) {
  durations.sort();

  final mean = durations.reduce((a, b) => a + b) / durations.length;

  // Calculate median and convert to double
  final double median = durations.length.isOdd
      ? durations[durations.length ~/ 2].toDouble()
      : (durations[durations.length ~/ 2 - 1] +
              durations[durations.length ~/ 2]) /
          2.0;

  final variance =
      durations.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) /
          durations.length;
  final stdDev = math.sqrt(variance);

  return TestStatistics(
    mean: mean,
    median: median,
    standardDev: stdDev,
    totalDuration: durations.reduce((a, b) => a + b),
    slowestTest: durations.last,
    fastestTest: durations.first,
  );
}

void printResults(
  Map<String, int> testDurations,
  TestStatistics stats,
  AnalyzerConfig config,
) {
  final sortedTests = testDurations.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Print statistics
  if (config.showStatistics) {
    print('\nTest Suite Statistics');
    print('-' * 60);
    print('Total Duration: ${formatDuration(stats.totalDuration)}');
    print('Average Duration: ${formatDuration(stats.mean.round())}');
    print('Median Duration: ${formatDuration(stats.median.round())}');
    print('Standard Deviation: ${formatDuration(stats.standardDev.round())}');
    print('Fastest Test: ${formatDuration(stats.fastestTest)}');
    print('Slowest Test: ${formatDuration(stats.slowestTest)}');
    print('Number of Tests: ${testDurations.length}');
    print('');
  }

  // Print test durations
  print('Test Duration Analysis');
  print('-' * 80);
  print('| ${padRight('Test Name', 50)} | ${padLeft('Duration', 20)} |');
  print('-' * 80);

  for (final test in sortedTests) {
    final duration = test.value;
    String output =
        '| ${padRight(test.key, 50)} | ${padRight(formatDuration(duration), 20)} |';

    if (config.useColors) {
      if (duration > config.slowTestThreshold) {
        output = '\x1B[31m$output\x1B[0m'; // Red for slow tests
      } else if (duration < stats.mean / 2) {
        output = '\x1B[32m$output\x1B[0m'; // Green for fast tests
      }
    }

    print(output);
  }
  print('-' * 80);

  // Print slow test warnings
  final slowTests =
      sortedTests.where((t) => t.value > config.slowTestThreshold).toList();
  if (slowTests.isNotEmpty) {
    print(
        '\n${slowTests.length} tests exceeded the ${config.slowTestThreshold}ms threshold:');
  }
}

String formatDuration(num milliseconds) {
  if (milliseconds < 1000) {
    return '${milliseconds.round()}ms';
  } else if (milliseconds < 60000) {
    return '${(milliseconds / 1000).toStringAsFixed(2)}s';
  } else {
    final minutes = (milliseconds / 60000).floor();
    final seconds = ((milliseconds % 60000) / 1000).toStringAsFixed(1);
    return '${minutes}m ${seconds}s';
  }
}

AnalyzerConfig parseArgs(List<String> args) {
  int? threshold;
  bool useColors = true;
  bool showStatistics = true;
  bool showGroups = true;

  for (final arg in args.skip(1)) {
    if (arg.startsWith('--threshold=')) {
      threshold = int.tryParse(arg.split('=')[1]);
    } else if (arg == '--no-color') {
      useColors = false;
    } else if (arg == '--no-stats') {
      showStatistics = false;
    } else if (arg == '--no-groups') {
      showGroups = false;
    }
  }

  return AnalyzerConfig(
    slowTestThreshold: threshold ?? 500,
    useColors: useColors,
    showStatistics: showStatistics,
    showGroups: showGroups,
  );
}

class TestInfo {
  final String name;
  final int startTime;
  final List<String> groups;

  TestInfo({
    required this.name,
    required this.startTime,
    this.groups = const [],
  });
}

String padRight(String text, int width) {
  if (text.length > width) {
    return '${text.substring(0, width - 3)}...';
  }
  return text.padRight(width);
}

String padLeft(String text, int width) {
  return text.padLeft(width);
}
