import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; // 📌 پکیج جدید نقشه
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safir_drivers/providers/registration_provider.dart'; 
import 'package:safir_drivers/utils/lang_helper.dart';

import '../../push_notifications/push_notification_system.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  MapLibreMapController? mapController;

  
  // 🎨 رنگ‌های برند سفیر
  static const Color brandPrimary = Color(0xFF145A41);   
  static const Color btnPrimary = Color(0xFF1B7A57);     
  static const Color btnPressed = Color(0xFF0F4A35);     
  static const Color cardBgLight = Color(0xFFEAF6F1);    
  static const Color successColor = Color(0xFF22C55E);   
  static const Color textOnBtn = Color(0xFFFFFFFF);      

  Position? currentPositionOfDriver;
  LatLng currentLatLng = const LatLng(34.5553, 69.2075); // کابل
  bool isDriverAvailable = false;
  bool isMapMoving = false;

  StreamSubscription<Position>? positionStreamHomePage;
  StreamSubscription<QuerySnapshot>? tripRequestStream;

  // 🗺️ آن‌کال شدن کنترلر هنگام ساخته شدن نقشه
  void _onMapCreated(MapLibreMapController controller) {

    mapController = controller;
  }

  // 🚀 جابه‌جایی انیمیشنی نقشه به موقعیت جدید
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!mounted || mapController == null) return;

    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: destLocation,
          zoom: destZoom,
        ),
      ),
    );
  }

  void listenForTripRequests() {
    tripRequestStream = FirebaseFirestore.instance
        .collection('rides')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          String tripID = change.doc.id;
          PushNotificationSystem().retrieveTripRequestInfo(tripID, context);
        }
      }
    });
  }

  getCurrentLiveLocationOfDriver() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position positionOfUser = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);
      
      currentPositionOfDriver = positionOfUser;

      if (!mounted) return;

      setState(() {
        currentLatLng = LatLng(currentPositionOfDriver!.latitude, currentPositionOfDriver!.longitude);
      });

      _animatedMapMove(currentLatLng, 16.0);
    } catch (e) {
      debugPrint("Error fetching location: $e");
    }
  }

  _loadDriverStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      isDriverAvailable = prefs.getBool('isDriverAvailable') ?? false;
      if (isDriverAvailable) {
        goOnlineNow();
      }
    });
  }

  _saveDriverStatus(bool status) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDriverAvailable', status);
  }

  goOnlineNow() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;

    if (currentPositionOfDriver != null) {
      await FirebaseFirestore.instance.collection("onlineDrivers").doc(uid).set({
        "driverId": uid,
        "latitude": currentPositionOfDriver!.latitude,
        "longitude": currentPositionOfDriver!.longitude,
        "last_active": FieldValue.serverTimestamp(),
        "status": "idle",
      }, SetOptions(merge: true));
    }

    await FirebaseFirestore.instance.collection("drivers").doc(uid).update({
      "newTripStatus": "waiting",
      "isOnline": true,
    }).catchError((e) {
      debugPrint("Error updating driver status: $e");
    });
  }

  setAndGetLocationUpdates() {
    positionStreamHomePage = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      currentPositionOfDriver = position;
      LatLng newLatLng = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        currentLatLng = newLatLng;
      });

      if (isDriverAvailable) {
        String uid = FirebaseAuth.instance.currentUser!.uid;
        FirebaseFirestore.instance.collection("onlineDrivers").doc(uid).set({
          "driverId": uid,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "last_active": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  goOfflineNow() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    
    await FirebaseFirestore.instance.collection("onlineDrivers").doc(uid).delete();

    await FirebaseFirestore.instance.collection("drivers").doc(uid).update({
      "newTripStatus": "offline",
      "isOnline": false,
    }).catchError((e) {
      debugPrint("Error going offline: $e");
    });

    positionStreamHomePage?.cancel();
    tripRequestStream?.cancel();
  }

  initializePushNotificationSystem() {
    PushNotificationSystem notificationSystem = PushNotificationSystem();
    notificationSystem.generateDeviceRegistrationToken();
    notificationSystem.startListeningForNewNotification(context);
  }

  @override
  void initState() {
    super.initState();
    _loadDriverStatus();
    initializePushNotificationSystem();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RegistrationProvider>(context, listen: false)
          .retrieveCurrentDriverInfo();
      getCurrentLiveLocationOfDriver();
    });
  }

  @override
  void dispose() {
    positionStreamHomePage?.cancel();
    tripRequestStream?.cancel();
    super.dispose();
  }

  void _showStatusChangeModal() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: cardBgLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.power_settings_new,
                  color: brandPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (!isDriverAvailable)
                    ? tr(context, 'change_to_online_title')
                    : tr(context, 'change_to_offline_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'IranYekan',
                  fontSize: 18,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                (!isDriverAvailable)
                    ? tr(context, 'change_to_online_desc')
                    : tr(context, 'change_to_offline_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IranYekan',
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (!isDriverAvailable) {
                          goOnlineNow();
                          setAndGetLocationUpdates();
                          Navigator.pop(context);
                          setState(() {
                            isDriverAvailable = true;
                          });
                          _saveDriverStatus(true);
                        } else {
                          goOfflineNow();
                          Navigator.pop(context);
                          setState(() {
                            isDriverAvailable = false;
                          });
                          _saveDriverStatus(false);
                        }
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.pressed)) {
                            return btnPressed;
                          }
                          return isDriverAvailable ? Colors.red.shade700 : btnPrimary;
                        }),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        elevation: WidgetStateProperty.all(0),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      child: Text(
                        tr(context, 'confirm'),
                        style: const TextStyle(
                          fontFamily: 'IranYekan', 
                          color: textOnBtn, 
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        tr(context, 'cancel'),
                        style: TextStyle(
                          fontFamily: 'IranYekan', 
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cardBgLight,
      body: Stack(
        children: [
          // 🗺️ نقشه MapLibre با استایل اختصاصی JSON
          MapLibreMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: currentLatLng,
              zoom: 16.0,
            ),
            styleString: 'assets/map/style.json', // 📍 فراخوانی استایل اختصاصی
            myLocationEnabled: false, // چون مارکر کاستوم مرکز صفحه داریم خاموش شد
            trackCameraPosition: true,
            
            onCameraIdle: () {
              if (isMapMoving) {
                setState(() {
                  isMapMoving = false;
                  if (mapController != null) {
                    currentLatLng = mapController!.cameraPosition!.target;
                  }
                });
              }
            },
          ),

          // 📍 مارکر مرکز نقشه
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 35),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                transform: Matrix4.translationValues(0, isMapMoving ? -14 : 0, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: brandPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isMapMoving ? 6 : 8,
                      height: isMapMoving ? 3 : 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(isMapMoving ? 0.3 : 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🔘 دکمه وضعیت آنلاین / آفلاین
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: SafeArea(
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: (isDriverAvailable ? Colors.red.shade900 : brandPrimary).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _showStatusChangeModal,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                        if (states.contains(WidgetState.pressed)) {
                          return btnPressed;
                        }
                        return isDriverAvailable ? Colors.red.shade600 : brandPrimary;
                      }),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      elevation: WidgetStateProperty.all(0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDriverAvailable ? successColor : Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isDriverAvailable 
                              ? tr(context, 'status_offline_btn') 
                              : tr(context, 'status_online_btn'),
                          style: const TextStyle(
                            fontFamily: 'IranYekan', 
                            color: textOnBtn, 
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 🎯 دکمه موقعیت من (GPS)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'recenter_btn',
              onPressed: getCurrentLiveLocationOfDriver,
              backgroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.my_location, color: brandPrimary, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}
