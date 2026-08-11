const graphDownsampleThreshold = 300;

List<T> lttbDownsample<T>(
  List<T> points,
  int threshold, {
  required double Function(T point) xValue,
  required double Function(T point) yValue,
}) {
  if (threshold <= 0 || points.isEmpty) {
    return List<T>.unmodifiable(<T>[]);
  }
  if (threshold >= points.length) {
    return List<T>.unmodifiable(points);
  }
  if (threshold == 1) {
    return List<T>.unmodifiable(<T>[points.first]);
  }
  if (threshold == 2) {
    return List<T>.unmodifiable(<T>[points.first, points.last]);
  }

  final sampled = <T>[points.first];
  var selectedIndex = 0;
  final bucketSize = (points.length - 2) / (threshold - 2);

  for (var bucket = 0; bucket < threshold - 2; bucket += 1) {
    final averageStart = ((bucket + 1) * bucketSize).floor() + 1;
    final averageEnd =
        (((bucket + 2) * bucketSize).floor() + 1).clamp(0, points.length);
    final averagePoint = _averagePoint(
      points,
      averageStart,
      averageEnd,
      xValue: xValue,
      yValue: yValue,
      fallback: points.last,
    );

    final rangeStart = (bucket * bucketSize).floor() + 1;
    final rangeEnd =
        (((bucket + 1) * bucketSize).floor() + 1).clamp(0, points.length - 1);
    var nextIndex = rangeStart;
    var maxArea = -1.0;

    for (var index = rangeStart; index < rangeEnd; index += 1) {
      final area = _triangleArea(
        points[selectedIndex],
        points[index],
        averagePoint,
        xValue: xValue,
        yValue: yValue,
      );
      if (area > maxArea) {
        maxArea = area;
        nextIndex = index;
      }
    }

    sampled.add(points[nextIndex]);
    selectedIndex = nextIndex;
  }

  sampled.add(points.last);
  return List<T>.unmodifiable(sampled);
}

_AveragePoint _averagePoint<T>(
  List<T> points,
  int start,
  int end, {
  required double Function(T point) xValue,
  required double Function(T point) yValue,
  required T fallback,
}) {
  if (start >= end || start >= points.length) {
    return _AveragePoint(x: xValue(fallback), y: yValue(fallback));
  }

  var xTotal = 0.0;
  var yTotal = 0.0;
  var count = 0;
  for (var index = start; index < end && index < points.length; index += 1) {
    xTotal += xValue(points[index]);
    yTotal += yValue(points[index]);
    count += 1;
  }

  return _AveragePoint(x: xTotal / count, y: yTotal / count);
}

double _triangleArea<T>(
  T left,
  T middle,
  _AveragePoint right, {
  required double Function(T point) xValue,
  required double Function(T point) yValue,
}) {
  final leftX = xValue(left);
  final leftY = yValue(left);
  final middleX = xValue(middle);
  final middleY = yValue(middle);
  return ((leftX - right.x) * (middleY - leftY) -
              (leftX - middleX) * (right.y - leftY))
          .abs() /
      2;
}

class _AveragePoint {
  const _AveragePoint({
    required this.x,
    required this.y,
  });

  final double x;
  final double y;
}
