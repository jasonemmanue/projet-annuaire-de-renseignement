import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeolocationService {

  // Vérifier et demander les permissions
  static Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  // Obtenir la position actuelle
  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // Convertir coordonnées en adresse
  static Future<String> getAddressFromCoordinates(
      double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return 'Adresse inconnue';
      final place = placemarks.first;
      return '${place.street}, ${place.locality}, ${place.country}';
    } catch (e) {
      return 'Adresse inconnue';
    }
  }

  // Convertir adresse en coordonnées
  static Future<LatLng?> getCoordinatesFromAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) return null;
      return LatLng(locations.first.latitude, locations.first.longitude);
    } catch (e) {
      return null;
    }
  }

  // Calculer distance entre deux points (en km)
  static double calculateDistance(
      double lat1, double lng1,
      double lat2, double lng2,
      ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }
}