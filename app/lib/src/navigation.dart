import 'package:flutter/widgets.dart';

/// Lets screens find out when another screen covers them (to stop the engine
/// while they are not visible).
final RouteObserver<ModalRoute<void>> appRouteObserver = RouteObserver<ModalRoute<void>>();
