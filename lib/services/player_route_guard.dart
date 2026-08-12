import 'package:flutter/material.dart';

/// Serializa la navegación hacia PlayerScreen para que un doble clic o dos
/// selecciones casi simultáneas nunca puedan apilar dos reproductores.
class PlayerRouteGuard {
  PlayerRouteGuard._();

  static bool _routeOpen = false;

  static bool get routeOpen => _routeOpen;

  static Future<T?> push<T>(BuildContext context, Route<T> route) async {
    if (_routeOpen) return null;

    // Se activa antes del primer await: dos eventos del mismo frame/event loop
    // no pueden atravesar la guarda al mismo tiempo.
    _routeOpen = true;
    try {
      return await Navigator.of(context).push<T>(route);
    } finally {
      _routeOpen = false;
    }
  }
}
