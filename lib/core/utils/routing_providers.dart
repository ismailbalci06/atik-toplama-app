import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing_service.dart';

/// Yol tarifi servisi — testlerde sahte bir getirici ile degistirilebilir.
final routingServiceProvider = Provider<RoutingService>(
  (ref) => RoutingService(),
);
