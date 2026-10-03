// ═══════════════════════════════════════════════════════════════════════════
//  KALAKRITI v21 — FIXED + LOCATION/DISTANCE/DELIVERY EDITION
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'notification_service.dart';
import 'admin_panel.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:table_calendar/table_calendar.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'firebase_options.dart';
import 'auth_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AI SERVICE
// ═══════════════════════════════════════════════════════════════════════════
class AIService {
  static const String _prod = 'https://kalak-shetra-ai.onrender.com';
  static const bool _useProd = true;

  static String get baseUrl {
    if (_useProd) return _prod;
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  static Future<Map<String, dynamic>?> analyzeProduct(
      Uint8List imageBytes, {String userDesc = ''}) async {
    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('$baseUrl/analyze-product'));
      req.fields['user_desc'] = userDesc;
      req.files.add(http.MultipartFile.fromBytes('file', imageBytes,
          filename: 'p.jpg'));
      final s = await req.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(s);
      if (res.statusCode != 200) {
        debugPrint('analyze ${res.statusCode}: ${res.body}');
        return null;
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('analyzeProduct: $e');
      return null;
    }
  }

  static Future<Uint8List?> removeBackground(Uint8List bytes) async {
    try {
      final req = http.MultipartRequest('POST',
          Uri.parse('$baseUrl/enhance'));
      req.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: 'img.jpg'));
      final s = await req.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(s);
      if (res.statusCode != 200) return null;
      final d = jsonDecode(res.body);
      if (d['image'] == null) return null;
      return base64Decode(d['image'] as String);
    } catch (e) {
      debugPrint('removeBackground: $e');
      return null;
    }
  }

  static Future<String?> chat(List<Map<String, String>> messages) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'messages': messages}),
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body)['reply'] as String?;
    } catch (e) {
      debugPrint('chat: $e');
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SPEECH SERVICE
// ═══════════════════════════════════════════════════════════════════════════
class SpeechService {
  final stt.SpeechToText _s = stt.SpeechToText();
  final FlutterTts _t = FlutterTts();
  bool _available = false;

  Future<bool> init() async {
    try {
      _available = await _s.initialize();
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  bool get available => _available;

  Future<void> listen(String localeId, void Function(String) onResult) async {
    if (!_available) return;
    try {
      await _s.listen(
        onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords),
        listenOptions: stt.SpeechListenOptions(localeId: localeId),
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _s.stop();
    } catch (_) {}
  }

  Future<void> speak(String text, String localeId) async {
    try {
      await _t.setLanguage(localeId);
      await _t.speak(text);
    } catch (_) {}
  }

  Future<void> stopSpeak() async {
    try {
      await _t.stop();
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  AUTH SERVICE
// ═══════════════════════════════════════════════════════════════════════════
class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<String?> signUp(String email, String password) async {
    try {
      final r = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      if (r.user != null) {
        await _db.collection('users').doc(r.user!.uid).set({
          'uid': r.user!.uid,
          'email': r.user!.email,
          'displayName': r.user!.email!.split('@').first,
          'bio': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _err(e);
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _err(e);
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> signOut() => _auth.signOut();

  static String _err(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
        return 'No account with that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LOCATION SERVICE  (NEW — device location + distance + ETA)
// ═══════════════════════════════════════════════════════════════════════════
class LocationService {
  /// Ask the OS for permission and return the current position.
  static Future<geo.Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      geo.LocationPermission permission =
          await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return null;
      }

      return await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint('getCurrentPosition: $e');
      return null;
    }
  }

  /// Haversine distance in km.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;

  /// Estimated delivery days from distance (km).
  /// 0-200km → 1-2d · 200-800 → 3-4d · 800-1500 → 5-6d · 1500+ → 6-8d
  static int deliveryDaysFor(double km) {
    if (km <= 200) return 2;
    if (km <= 500) return 3;
    if (km <= 800) return 4;
    if (km <= 1200) return 5;
    if (km <= 1800) return 6;
    if (km <= 2500) return 7;
    return 8;
  }

  /// Rough delivery fee from distance in km.
  static double deliveryFeeFor(double km) {
    if (km <= 100) return 0;      // local pickup zone
    if (km <= 500) return 40;
    if (km <= 1200) return 80;
    if (km <= 2000) return 120;
    return 180;
  }

  /// Delivery window string. e.g. "20 Sep – 22 Sep · 3 days"
  static String deliveryWindow(double km) {
    final days = deliveryDaysFor(km);
    final from = DateTime.now().add(Duration(days: days));
    final to = DateTime.now().add(Duration(days: days + 1));
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${from.day} ${m[from.month - 1]} – ${to.day} ${m[to.month - 1]} · $days day${days != 1 ? 's' : ''}';
  }

  /// Reverse-geocode a LatLng to a readable locality (nearest Indian city).
  /// Offline fallback — uses a small lookup of major cities.
  static String nearestCity(double lat, double lng) {
    const cities = <String, List<double>>{
      'Delhi, DL': [28.6139, 77.2090],
      'Mumbai, MH': [19.0760, 72.8777],
      'Kolkata, WB': [22.5726, 88.3639],
      'Chennai, TN': [13.0827, 80.2707],
      'Bengaluru, KA': [12.9716, 77.5946],
      'Hyderabad, TS': [17.3850, 78.4867],
      'Jaipur, RJ': [26.9124, 75.7873],
      'Ahmedabad, GJ': [23.0225, 72.5714],
      'Varanasi, UP': [25.3176, 82.9739],
      'Kanchipuram, TN': [12.8342, 79.7036],
      'Srinagar, JK': [34.0837, 74.7973],
      'Kochi, KL': [9.9312, 76.2673],
      'Amritsar, PB': [31.6340, 74.8723],
      'Pochampally, TS': [17.5626, 78.7000],
      'Moradabad, UP': [28.8386, 78.7733],
      'Bhuj, GJ': [23.2420, 69.6669],
      'Sambalpur, OD': [21.4669, 83.9812],
      'Chanderi, MP': [24.7138, 78.1372],
    };
    double best = double.infinity;
    String name = 'India';
    cities.forEach((city, c) {
      final d = distanceKm(lat, lng, c[0], c[1]);
      if (d < best) {
        best = d;
        name = city;
      }
    });
    return name;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TRANSLATIONS
// ═══════════════════════════════════════════════════════════════════════════
const Map<String, Map<String, String>> kStrings = {
  'en': {
    'brand': 'Kalakriti', 'tagline': 'Where tradition meets expression',
    'tab_shop': 'Shop', 'tab_add': 'Upload', 'tab_cart': 'Cart', 'tab_profile': 'You',
    'search_hint': 'Search sarees, kurtis, jewelry…',
    'fair_feed': 'Fair Feed · equal visibility for every seller',
    'new_badge': 'NEW', 'added_to_cart': 'added to cart',
    'add_to_cart': 'Add to Cart', 'buy_now': 'Buy Now',
    'product': 'Product', 'description': 'Description', 'tags': 'Tags',
    'list_new_craft': 'List a New Craft', 'category': 'Category', 'title': 'Title',
    'title_hint': 'e.g. "Banarasi Silk Saree"',
    'desc_hint': 'Speak or type the story behind this piece…',
    'price': 'Price (₹)', 'price_hint': 'e.g. 1200',
    'save_listing': 'Publish Listing', 'remove_bg': 'Remove Background',
    'analyzing': 'AI analyzing…', 'take_photo': 'Take Photo',
    'from_gallery': 'Choose from Gallery', 'add_more': 'Add more',
    'photos': 'Photos', 'voice_lang': 'Voice Language',
    'empty_cart': 'Your cart is empty', 'total': 'Total',
    'checkout': 'Checkout', 'order_placed': 'Order placed!',
    'my_shop': 'My Shop', 'artisan_account': 'Artisan Account',
    'my_products': 'My Products', 'no_products': 'No products yet.',
    'purchased': 'Purchased', 'fill_required': 'Fill title, price and pick an image',
    'uploaded': 'Product published!', 'no_match': 'No products match.',
    'select_lang': 'Display Language', 'loading': 'Loading…',
    'logout': 'Sign Out', 'settings': 'Settings',
    'display_name': 'Display Name', 'bio': 'About your craft',
    'bio_hint': 'Tell buyers about yourself…',
    'save_changes': 'Save Changes', 'saved': 'Saved!',
    'language': 'Language', 'account': 'Account',
    'chat_title': 'Kalakriti Assistant', 'chat_hint': 'Ask about pricing, tips…',
    'chat_empty': 'Ask me anything — pricing help, festival tips.',
    'chat_error': 'Assistant unavailable. Try again.',
    'location': 'Location', 'location_hint': 'e.g. Jaipur, Rajasthan',
    'delivery': 'Delivery Info', 'delivery_hint': 'e.g. Ships in 3-5 days',
    'delete': 'Delete', 'delete_confirm': 'Delete this listing?',
    'deleted': 'Listing deleted', 'share': 'Share', 'copied': 'Copied!',
    'cancel': 'Cancel', 'delete_btn': 'Delete',
    'orders': 'Orders', 'wishlist': 'Wishlist',
    'no_orders': 'No orders yet', 'no_wishlist': 'Nothing in wishlist',
    'ai_filled': 'AI filled the form — review and edit',
    'ai_failed': 'AI analysis failed. Try again.',
    'bg_removed': 'Background removed!', 'bg_failed': 'Background removal failed',
    'mic_unavailable': 'Voice not available on this device/browser',
    'reviews': 'Reviews', 'write_review': 'Write a review',
    'no_reviews': 'No reviews yet. Be the first!',
    'rating': 'Rating', 'your_review': 'Your review',
    'submit_review': 'Submit Review', 'review_added': 'Review submitted!',
    'seller': 'Seller', 'seller_products': 'Products by this seller',
    'notifications': 'Notifications', 'no_notifications': 'No notifications yet',
    'addresses': 'Addresses', 'add_address': 'Add Address', 'edit_address': 'Edit Address',
    'full_name': 'Full Name', 'phone': 'Phone', 'address_line': 'Address',
    'city': 'City', 'state': 'State', 'pincode': 'Pincode',
    'save_address': 'Save Address', 'default_address': 'Default', 'set_default': 'Set as default',
    'payment': 'Payment', 'payment_method': 'Payment Method',
    'cod': 'Cash on Delivery', 'upi': 'UPI', 'card': 'Credit / Debit Card', 'netbanking': 'Net Banking',
    'place_order': 'Place Order', 'order_confirmed': 'Order confirmed!',
    'order_id': 'Order ID', 'track_order': 'Track Order', 'order_tracking': 'Order Tracking',
    'confirmed': 'Confirmed', 'packed': 'Packed', 'shipped': 'Shipped',
    'delivered': 'Delivered', 'out_for_delivery': 'Out for delivery',
    'help': 'Help & FAQ', 'about': 'About Kalakriti', 'coupons': 'Coupons',
    'apply_coupon': 'Apply Coupon', 'coupon_applied': 'Coupon applied!',
    'invalid_coupon': 'Invalid coupon code',
    'subtotal': 'Subtotal', 'discount': 'Discount',
    'delivery_fee': 'Delivery', 'grand_total': 'Grand Total',
    'trending': 'Trending now', 'recently_viewed': 'Recently viewed',
    'filters': 'Filters', 'sort_by': 'Sort by',
    'price_low': 'Price: Low → High', 'price_high': 'Price: High → Low',
    'newest': 'Newest first', 'rating_high': 'Top rated',
    'min_price': 'Min price', 'max_price': 'Max price',
    'apply_filters': 'Apply Filters', 'clear_filters': 'Clear',
    'results': 'Results', 'compare': 'Compare',
    'skip': 'Skip', 'next': 'Next', 'get_started': 'Get Started',
    'onboard_1_title': 'Discover authentic crafts',
    'onboard_1_desc': 'Handpicked sarees, jewelry and handicrafts from artisans across India.',
    'onboard_2_title': 'AI-powered listings',
    'onboard_2_desc': 'Snap a photo, speak your story — our AI writes the listing.',
    'onboard_3_title': 'Fair for every seller',
    'onboard_3_desc': 'Every artisan gets equal visibility. No paid boosts. Just craft.',
    'map': 'Artisan Map', 'calendar': 'Calendar',
    'festival_plan': 'Plan your listings 2 weeks ahead for maximum sales.',
    'no_events': 'No events. Perfect day to craft! 🧵',
    // NEW
    'near_me': 'Near me',
    'near_me_hint': 'Show products within 300 km',
    'sort_distance': 'Sort: Nearest first',
    'pick_on_map': 'Pick on Map',
    'use_my_location': 'Use My Location',
    'set_location': 'Set Your Location',
    'set_location_desc': 'Tap on the map to pin your shop location. Buyers will see the exact distance and delivery time.',
    'confirm_location': 'Confirm Location',
    'location_set': 'Location set!',
    'getting_location': 'Getting location…',
    'location_denied': 'Location permission denied',
    'arrives_in': 'Arrives in',
    'away': 'away',
    'from_you': 'from you',
    'delivery_eta': 'Delivery ETA',
    'delivery_charge': 'Delivery charge',
    'free_delivery': 'FREE delivery',
    'shipping_from': 'Ships from',
    'distance_filter': 'Distance',
  },
};

// ═══════════════════════════════════════════════════════════════════════════
//  PALETTE
// ═══════════════════════════════════════════════════════════════════════════
class K {
  static const cream = Color(0xFFF6EEDE);
  static const paper = Color(0xFFFFF9EC);
  static const maroon = Color(0xFF7A2331);
  static const deepMaroon = Color(0xFF5A1825);
  static const gold = Color(0xFFD9A441);
  static const goldLight = Color(0xFFE8C57A);
  static const terracotta = Color(0xFFC1652F);
  static const leaf = Color(0xFF3F6E52);
  static const indigo = Color(0xFF1F3B4D);
  static const ink = Color(0xFF3B2418);
  static const inkSoft = Color(0xFF6B4F3A);
}

const kCategories = <String>['All', 'Sarees', 'Dresses', 'Handicrafts', 'Jewelry'];

IconData iconFor(String c) {
  switch (c) {
    case 'Sarees':
      return Icons.checkroom;
    case 'Dresses':
      return Icons.woman;
    case 'Handicrafts':
      return Icons.handyman;
    case 'Jewelry':
      return Icons.diamond;
    default:
      return Icons.shopping_bag;
  }
}

Color colorFor(String c) {
  switch (c) {
    case 'Sarees':
      return K.maroon;
    case 'Dresses':
      return K.terracotta;
    case 'Handicrafts':
      return K.leaf;
    case 'Jewelry':
      return K.gold;
    default:
      return K.indigo;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MODELS
// ═══════════════════════════════════════════════════════════════════════════
class Product {
  final String id;
  final String title;
  final String description;
  final String descriptionHi;
  final String category;
  final String sellerId;
  final String sellerName;
  final String sellerPhotoUrl;
  final double price;
  final List<Uint8List> images;
  final List<String> imageUrls;
  final DateTime createdAt;
  final List<String> keywords;
  final String location;
  final String deliveryInfo;
  final double rating;
  final double lat;
  final double lng;
  final int ratingCount;
  final int views;

  Product({
    required this.id,
    required this.title,
    required this.description,
    this.descriptionHi = '',
    required this.price,
    this.images = const <Uint8List>[],
    this.imageUrls = const <String>[],
    required this.category,
    required this.sellerId,
    required this.sellerName,
    this.sellerPhotoUrl = '',
    required this.createdAt,
    required this.keywords,
    this.location = '',
    this.deliveryInfo = '',
    this.rating = 0,
    this.ratingCount = 0,
    this.views = 0,
    this.lat = 0,
    this.lng = 0,
  });

  bool get isNew => DateTime.now().difference(createdAt).inDays < 7;

  bool get hasLocation => lat != 0 || lng != 0;

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'title': title,
        'description': description,
        'descriptionHi': descriptionHi,
        'price': price,
        'category': category,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'sellerPhotoUrl': sellerPhotoUrl,
        'createdAt': Timestamp.fromDate(createdAt),
        'keywords': keywords,
        'imageBytes': images.map((b) => base64Encode(b)).toList(),
        'imageUrls': imageUrls,
        'location': location,
        'deliveryInfo': deliveryInfo,
        'rating': rating,
        'ratingCount': ratingCount,
        'views': views,
        'lat': lat,
        'lng': lng,
      };

  factory Product.fromFirestore(Map<String, dynamic> j) {
    DateTime created;
    final raw = j['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate();
    } else if (raw is String) {
      created = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    final List<Uint8List> imgs = <Uint8List>[];
    final rawImgs = j['imageBytes'];
    if (rawImgs is List) {
      for (final b in rawImgs) {
        if (b is String && b.isNotEmpty) {
          try {
            imgs.add(base64Decode(b));
          } catch (_) {}
        }
      }
    } else if (rawImgs is String && rawImgs.isNotEmpty) {
      try {
        imgs.add(base64Decode(rawImgs));
      } catch (_) {}
    }

    return Product(
      id: j['id'] ?? '',
      title: j['title'] ?? '',
      description: j['description'] ?? '',
      descriptionHi: j['descriptionHi'] ?? '',
      price: (j['price'] as num?)?.toDouble() ?? 0,
      images: imgs,
      imageUrls: List<String>.from(j['imageUrls'] ?? []),
      category: j['category'] ?? 'Handicrafts',
      sellerId: j['sellerId'] ?? '',
      sellerName: j['sellerName'] ?? '',
      sellerPhotoUrl: j['sellerPhotoUrl'] ?? '',
      createdAt: created,
      keywords: List<String>.from(j['keywords'] ?? []),
      location: j['location'] ?? '',
      deliveryInfo: j['deliveryInfo'] ?? '',
      rating: (j['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
      views: (j['views'] as num?)?.toInt() ?? 0,
      lat: (j['lat'] as num?)?.toDouble() ?? 0,
      lng: (j['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Review {
  final String id;
  final String productId;
  final String userId;
  final String userName;
  final String text;
  final double rating;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'text': text,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] ?? '',
        productId: m['productId'] ?? '',
        userId: m['userId'] ?? '',
        userName: m['userName'] ?? '',
        rating: (m['rating'] as num?)?.toDouble() ?? 0,
        text: m['text'] ?? '',
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );
}

class Address {
  final String id;
  final String fullName;
  final String phone;
  final String line;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;
  final double lat;
  final double lng;

  Address({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.line,
    required this.city,
    required this.state,
    required this.pincode,
    this.isDefault = false,
    this.lat = 0,
    this.lng = 0,
  });

  String get oneLine => '$line, $city, $state - $pincode';

  Map<String, dynamic> toMap() => {
        'id': id,
        'fullName': fullName,
        'phone': phone,
        'line': line,
        'city': city,
        'state': state,
        'pincode': pincode,
        'isDefault': isDefault,
        'lat': lat,
        'lng': lng,
      };

  factory Address.fromMap(Map<String, dynamic> m) => Address(
        id: m['id'] ?? '',
        fullName: m['fullName'] ?? '',
        phone: m['phone'] ?? '',
        line: m['line'] ?? '',
        city: m['city'] ?? '',
        state: m['state'] ?? '',
        pincode: m['pincode'] ?? '',
        isDefault: m['isDefault'] == true,
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
      );
}

class Coupon {
  final String code;
  final String description;
  final int percent;
  final double maxDiscount;
  final double minCart;

  const Coupon({
    required this.code,
    required this.percent,
    required this.maxDiscount,
    required this.minCart,
    required this.description,
  });
}

const kCoupons = <Coupon>[
  Coupon(
      code: 'WELCOME10',
      percent: 10,
      maxDiscount: 500,
      minCart: 1000,
      description: '10% off up to ₹500 on orders above ₹1000'),
  Coupon(
      code: 'FESTIVE20',
      percent: 20,
      maxDiscount: 1500,
      minCart: 3000,
      description: '20% off up to ₹1500 on orders above ₹3000'),
  Coupon(
      code: 'HANDLOOM15',
      percent: 15,
      maxDiscount: 800,
      minCart: 1500,
      description: '15% off up to ₹800 on orders above ₹1500'),
];

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });
}

class UserProfile {
  final String uid;
  final String email;
  String displayName;
  String bio;
  String? photoUrl;
  double lat;
  double lng;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.bio = '',
    this.photoUrl,
    this.lat = 0,
    this.lng = 0,
  });

  factory UserProfile.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: d['uid'] ?? '',
      email: d['email'] ?? '',
      displayName: d['displayName'] ?? '',
      bio: d['bio'] ?? '',
      photoUrl: d['photoUrl'],
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PROVIDER
// ═══════════════════════════════════════════════════════════════════════════
class ProductProvider extends ChangeNotifier {
  final List<Product> _products = [];
  final Map<String, int> _cart = {};
  final Set<String> _wish = {};
  final Set<String> _friends = {};
  final Set<String> _sentRequests = {};
  final List<Map<String, dynamic>> _orders = [];
  final List<Address> _addresses = [];
  final List<AppNotification> _notifications = [];
  final List<String> _recentlyViewed = [];
  String _lang = 'en';
  bool _loaded = false;
  bool _onboarded = false;
  UserProfile? _me;

  // NEW: user's location
  double _userLat = 0;
  double _userLng = 0;
  String _userCity = '';

  final _db = FirebaseFirestore.instance;

  ProductProvider() {
    _init();
  }

  List<Product> get products => _products;
  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? 'anon';

  String get currentUserName {
    final me = _me;
    if (me != null && me.displayName.isNotEmpty) return me.displayName;
    return FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'My Shop';
  }

  Map<String, int> get cart => _cart;
  Set<String> get wishlist => _wish;
  Set<String> get friends => _friends;
  Set<String> get sentRequests => _sentRequests;
  List<Map<String, dynamic>> get orders => _orders;
  List<Address> get addresses => _addresses;
  List<AppNotification> get notifications => _notifications;
  List<String> get recentlyViewed => _recentlyViewed;
  String get lang => _lang;
  bool get loaded => _loaded;
  bool get onboarded => _onboarded;
  UserProfile? get me => _me;

  double get userLat => _userLat;
  double get userLng => _userLng;
  String get userCity => _userCity;
  bool get hasUserLocation => _userLat != 0 || _userLng != 0;

  int get cartCount => _cart.values.fold(0, (a, b) => a + b);

  double get cartTotal {
    double t = 0;
    _cart.forEach((id, q) {
      final p = _products.where((x) => x.id == id).toList();
      if (p.isNotEmpty) t += p.first.price * q;
    });
    return t;
  }

  /// Total distance-based delivery fee across all cart items.
  double get cartDeliveryFee {
    if (_cart.isEmpty) return 0;
    double maxFee = 0;
    _cart.forEach((id, _) {
      final list = _products.where((x) => x.id == id).toList();
      if (list.isNotEmpty) {
        final km = distanceToProduct(list.first);
        final fee = LocationService.deliveryFeeFor(km);
        if (fee > maxFee) maxFee = fee;
      }
    });
    return maxFee;
  }

  /// Max estimated delivery days for the cart.
  int get cartDeliveryDays {
    int maxD = 0;
    _cart.forEach((id, _) {
      final list = _products.where((x) => x.id == id).toList();
      if (list.isNotEmpty) {
        final km = distanceToProduct(list.first);
        final d = LocationService.deliveryDaysFor(km);
        if (d > maxD) maxD = d;
      }
    });
    return maxD;
  }

  double distanceToProduct(Product p) {
    if (!hasUserLocation || !p.hasLocation) return 800; // fallback
    return LocationService.distanceKm(_userLat, _userLng, p.lat, p.lng);
  }

  String t(String key) => kStrings[_lang]?[key] ?? kStrings['en']?[key] ?? key;

  void setLang(String l) {
    _lang = l;
    _saveLocal();
    notifyListeners();
  }

  Future<void> setUserLocation(double lat, double lng) async {
    _userLat = lat;
    _userLng = lng;
    _userCity = LocationService.nearestCity(lat, lng);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('userLat', lat);
    await prefs.setDouble('userLng', lng);
    await prefs.setString('userCity', _userCity);
    // also persist to profile if logged in
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _db.collection('users').doc(uid).set(
            {'lat': lat, 'lng': lng}, SetOptions(merge: true));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cd = prefs.getString('cart_v21');
    if (cd != null) {
      final m = jsonDecode(cd) as Map<String, dynamic>;
      _cart.clear();
      m.forEach((k, v) {
        _cart[k] = v as int;
      });
    }
    _wish.addAll(prefs.getStringList('wish_v21') ?? []);
    _friends.addAll(prefs.getStringList('friends_v21') ?? []);
    _sentRequests.addAll(prefs.getStringList('sentreq_v21') ?? []);
    _lang = prefs.getString('lang_v21') ?? 'en';
    _onboarded = prefs.getBool('onboarded_v21') ?? false;
    _recentlyViewed.addAll(prefs.getStringList('recent_v21') ?? []);
    _userLat = prefs.getDouble('userLat') ?? 0;
    _userLng = prefs.getDouble('userLng') ?? 0;
    _userCity = prefs.getString('userCity') ?? '';

    final addrJson = prefs.getString('addresses_v21');
    if (addrJson != null) {
      try {
        final list = jsonDecode(addrJson) as List;
        for (final a in list) {
          _addresses.add(Address.fromMap(a as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists) {
          _me = UserProfile.fromDoc(doc);
          if (_userLat == 0 && _me!.lat != 0) {
            _userLat = _me!.lat;
            _userLng = _me!.lng;
            _userCity = LocationService.nearestCity(_userLat, _userLng);
          }
        }
      } catch (_) {}

      try {
        final snap = await _db
            .collection('orders')
            .where('userId', isEqualTo: uid)
            .orderBy('placedAt', descending: true)
            .limit(50)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          _orders.add({
            'id': d.id,
            'total': data['total'],
            'itemCount': data['itemCount'],
            'status': data['status'] ?? 'confirmed',
            'placedAt': (data['placedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
          });
        }
      } catch (_) {}
    }

    try {
      final existing = await _db.collection('products').limit(1).get();
      if (existing.docs.isEmpty) {
        await _seed();
      }
    } catch (_) {}

    _db
        .collection('products')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        _products.clear();
        for (final doc in snap.docs) {
          try {
            _products.add(Product.fromFirestore(doc.data()));
          } catch (_) {}
        }
        _loaded = true;
        notifyListeners();
      },
      onError: (e) {
        _loaded = true;
        notifyListeners();
      },
    );
  }

  Future<void> setOnboarded() async {
    _onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded_v21', true);
    notifyListeners();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cart_v21', jsonEncode(_cart));
    await prefs.setStringList('wish_v21', _wish.toList());
    await prefs.setStringList('friends_v21', _friends.toList());
    await prefs.setStringList('sentreq_v21', _sentRequests.toList());
    await prefs.setString('lang_v21', _lang);
    await prefs.setStringList('recent_v21', _recentlyViewed);
    await prefs.setString(
        'addresses_v21', jsonEncode(_addresses.map((a) => a.toMap()).toList()));
  }

  void trackView(String id) {
    _recentlyViewed.remove(id);
    _recentlyViewed.insert(0, id);
    if (_recentlyViewed.length > 20) {
      _recentlyViewed.removeRange(20, _recentlyViewed.length);
    }
    _saveLocal();
    notifyListeners();
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? photoUrl,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = <String, dynamic>{};
    if (displayName != null) {
      data['displayName'] = displayName;
    }
    if (bio != null) {
      data['bio'] = bio;
    }
    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }
    try {
      await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
    } catch (_) {}
    _me = UserProfile(
      uid: uid,
      email: FirebaseAuth.instance.currentUser?.email ?? '',
      displayName: displayName ?? _me?.displayName ?? '',
      bio: bio ?? _me?.bio ?? '',
      photoUrl: photoUrl ?? _me?.photoUrl,
      lat: _userLat,
      lng: _userLng,
    );
    notifyListeners();
  }

  Future<void> addProduct({
    required String title,
    required String description,
    String descriptionHi = '',
    required double price,
    List<Uint8List> images = const <Uint8List>[],
    required String category,
    String location = '',
    String deliveryInfo = '',
    double lat = 0,
    double lng = 0,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final p = Product(
      id: const Uuid().v4(),
      title: title,
      description: description,
      descriptionHi: descriptionHi,
      price: price,
      images: images,
      category: category,
      sellerId: uid,
      sellerName: currentUserName,
      createdAt: DateTime.now(),
      keywords: _kw(title, description),
      location: location,
      deliveryInfo: deliveryInfo,
      lat: lat != 0 ? lat : _userLat,
      lng: lng != 0 ? lng : _userLng,
    );
    await _db.collection('products').doc(p.id).set(p.toFirestore());
    _addNotification('Listing published', '"${p.title}" is now live.');
  }

  Future<void> deleteProduct(String id) async {
    await _db.collection('products').doc(id).delete();
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> placeOrder(double total, int itemCount,
      {String status = 'confirmed',
      String? couponCode,
      double deliveryFee = 0,
      int deliveryDays = 3,
      String deliveryAddress = ''}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final orderId = const Uuid().v4().substring(0, 8).toUpperCase();
    _orders.insert(0, {
      'id': orderId,
      'total': total,
      'itemCount': itemCount,
      'status': status,
      'coupon': couponCode,
      'placedAt': DateTime.now(),
      'deliveryDays': deliveryDays,
    });
    notifyListeners();
    _addNotification('Order placed',
        'Order #$orderId confirmed. Total ₹${total.toStringAsFixed(0)}');
    if (uid == null) return;
    try {
      await _db.collection('orders').add({
        'userId': uid,
        'orderId': orderId,
        'total': total,
        'itemCount': itemCount,
        'status': status,
        'coupon': couponCode,
        'deliveryFee': deliveryFee,
        'deliveryDays': deliveryDays,
        'deliveryAddress': deliveryAddress,
        'placedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void addToCart(String id) {
    _cart[id] = (_cart[id] ?? 0) + 1;
    _saveLocal();
    notifyListeners();
  }

  void removeFromCart(String id) {
    if (!_cart.containsKey(id)) return;
    if (_cart[id]! > 1) {
      _cart[id] = _cart[id]! - 1;
    } else {
      _cart.remove(id);
    }
    _saveLocal();
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _saveLocal();
    notifyListeners();
  }

  void toggleWish(String id) {
    if (_wish.contains(id)) {
      _wish.remove(id);
    } else {
      _wish.add(id);
    }
    _saveLocal();
    notifyListeners();
  }

  bool isWished(String id) => _wish.contains(id);
  bool isFriend(String sellerId) => _friends.contains(sellerId);
  bool hasSentRequest(String sellerId) => _sentRequests.contains(sellerId);

  void sendFriendRequest(String sellerId) {
    _sentRequests.add(sellerId);
    _saveLocal();
    notifyListeners();
    _addNotification('Friend request sent',
        'Waiting for the artisan to accept your request.');
  }

  void cancelFriendRequest(String sellerId) {
    _sentRequests.remove(sellerId);
    _saveLocal();
    notifyListeners();
  }

  void removeFriend(String sellerId) {
    _friends.remove(sellerId);
    _sentRequests.remove(sellerId);
    _saveLocal();
    notifyListeners();
  }

  void acceptFriend(String sellerId) {
    _sentRequests.remove(sellerId);
    _friends.add(sellerId);
    _saveLocal();
    notifyListeners();
    _addNotification('Friend added',
        'You are now friends with this artisan. Chat anytime!');
  }

  List<Product> productsBySeller(String sellerId) =>
      _products.where((p) => p.sellerId == sellerId).toList();

  List<Map<String, dynamic>> get friendList {
    final result = <Map<String, dynamic>>[];
    for (final fid in _friends) {
      final list = _products.where((x) => x.sellerId == fid).toList();
      if (list.isEmpty) continue;
      final first = list.first;
      result.add({
        'id': fid,
        'name': first.sellerName.split(',').first.trim(),
        'city': first.location,
        'photo': first.sellerPhotoUrl,
        'products': list.length,
      });
    }
    return result;
  }

  void addAddress(Address a) {
    if (a.isDefault) {
      for (int i = 0; i < _addresses.length; i++) {
        final x = _addresses[i];
        _addresses[i] = Address(
            id: x.id,
            fullName: x.fullName,
            phone: x.phone,
            line: x.line,
            city: x.city,
            state: x.state,
            pincode: x.pincode,
            isDefault: false,
            lat: x.lat,
            lng: x.lng);
      }
    }
    _addresses.add(a);
    if (_addresses.length == 1) {
      final x = _addresses[0];
      _addresses[0] = Address(
          id: x.id,
          fullName: x.fullName,
          phone: x.phone,
          line: x.line,
          city: x.city,
          state: x.state,
          pincode: x.pincode,
          isDefault: true,
          lat: x.lat,
          lng: x.lng);
    }
    _saveLocal();
    notifyListeners();
  }

  void removeAddress(String id) {
    _addresses.removeWhere((a) => a.id == id);
    _saveLocal();
    notifyListeners();
  }

  void setDefaultAddress(String id) {
    for (int i = 0; i < _addresses.length; i++) {
      final a = _addresses[i];
      _addresses[i] = Address(
          id: a.id,
          fullName: a.fullName,
          phone: a.phone,
          line: a.line,
          city: a.city,
          state: a.state,
          pincode: a.pincode,
          isDefault: a.id == id,
          lat: a.lat,
          lng: a.lng);
    }
    _saveLocal();
    notifyListeners();
  }

  Address? get defaultAddress {
    if (_addresses.isEmpty) return null;
    return _addresses.firstWhere((a) => a.isDefault,
        orElse: () => _addresses.first);
  }

  void _addNotification(String title, String body) {
    _notifications.insert(
        0,
        AppNotification(
            id: const Uuid().v4(),
            title: title,
            body: body,
            createdAt: DateTime.now()));
    notifyListeners();
  }

  void markAllNotificationsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      _notifications[i] = AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          createdAt: n.createdAt,
          read: true);
    }
    notifyListeners();
  }

  int get unreadNotifCount => _notifications.where((n) => !n.read).length;

  List<Product> getRecommendedFeed() {
    if (_products.isEmpty) return [];
    final by = <String, List<Product>>{};
    for (final p in _products) {
      by.putIfAbsent(p.sellerId, () => []).add(p);
    }
    for (final l in by.values) {
      l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final feed = <Product>[];
    int i = 0;
    bool added = true;
    while (added) {
      added = false;
      for (final s in by.keys) {
        if (i < by[s]!.length) {
          feed.add(by[s]![i]);
          added = true;
        }
      }
      i++;
    }
    return feed;
  }

  /// NEW: sorted by distance from user
  List<Product> sortedByDistance(List<Product> list) {
    final copy = List<Product>.from(list);
    if (!hasUserLocation) return copy;
    copy.sort((a, b) => distanceToProduct(a).compareTo(distanceToProduct(b)));
    return copy;
  }

  List<Product> get trending {
    final list = List<Product>.from(_products);
    list.sort((a, b) => b.views.compareTo(a.views));
    return list.take(8).toList();
  }

  List<String> _kw(String t, String d) {
    final w = '$t $d'.toLowerCase().split(RegExp(r'\W+'));
    const stop = <String>{
      'the','a','an','and','or','in','on','at','to','for','of','with','by',
      'is','are','this','that',
    };
    final f = <String, int>{};
    for (final x in w) {
      if (x.length > 2 && !stop.contains(x)) {
        f[x] = (f[x] ?? 0) + 1;
      }
    }
    return (f.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    final rng = math.Random();
    final sellers = <Map<String, dynamic>>[
      {'id':'s01','name':'Meera Devi','photo':'https://i.pravatar.cc/150?img=47','city':'Varanasi, UP','lat':25.3176,'lng':82.9739},
      {'id':'s02','name':'Ravi Kumar','photo':'https://i.pravatar.cc/150?img=12','city':'Pochampally, TS','lat':17.5626,'lng':78.7000},
      {'id':'s03','name':'Lakshmi Weaves','photo':'https://i.pravatar.cc/150?img=44','city':'Kanchipuram, TN','lat':12.8342,'lng':79.7036},
      {'id':'s04','name':'Anita Crafts','photo':'https://i.pravatar.cc/150?img=23','city':'Moradabad, UP','lat':28.8386,'lng':78.7733},
      {'id':'s05','name':'Jaipur Arts','photo':'https://i.pravatar.cc/150?img=32','city':'Jaipur, RJ','lat':26.9124,'lng':75.7873},
      {'id':'s06','name':'Bengal Crafts','photo':'https://i.pravatar.cc/150?img=58','city':'Kolkata, WB','lat':22.5726,'lng':88.3639},
      {'id':'s07','name':'Gujarat Weaves','photo':'https://i.pravatar.cc/150?img=29','city':'Bhuj, GJ','lat':23.2420,'lng':69.6669},
      {'id':'s08','name':'Odisha Ikat','photo':'https://i.pravatar.cc/150?img=17','city':'Sambalpur, OD','lat':21.4669,'lng':83.9812},
      {'id':'s09','name':'Chanderi Looms','photo':'https://i.pravatar.cc/150?img=50','city':'Chanderi, MP','lat':24.7138,'lng':78.1372},
      {'id':'s10','name':'Kerala Crafts','photo':'https://i.pravatar.cc/150?img=40','city':'Kochi, KL','lat':9.9312,'lng':76.2673},
      {'id':'s11','name':'Punjab Handlooms','photo':'https://i.pravatar.cc/150?img=60','city':'Amritsar, PB','lat':31.6340,'lng':74.8723},
      {'id':'s12','name':'Kashmir Shawls','photo':'https://i.pravatar.cc/150?img=5','city':'Srinagar, JK','lat':34.0837,'lng':74.7973},
    ];

    final templates = <String, List<List<String>>>{
      'Sarees': [
        ['Banarasi Silk Saree', 'Pure Banarasi silk with intricate gold zari woven on handloom.'],
        ['Kanjivaram Silk Saree', 'Authentic Kanjivaram with pure zari and temple border.'],
        ['Pochampally Ikat Saree', 'Handwoven Ikat from Telangana with geometric patterns.'],
        ['Bandhani Cotton Saree', 'Traditional Bandhani tie-dye in vibrant festive colours.'],
        ['Chanderi Cotton Saree', 'Sheer Chanderi weave with subtle gold butis.'],
        ['Mysore Silk Saree', 'Pure Mysore silk with contrast pallu and rich texture.'],
        ['Tussar Silk Saree', 'Handwoven Tussar silk with Madhubani painted pallu.'],
        ['Sambalpuri Saree', 'Traditional Odisha Ikat with temple motifs.'],
        ['Patola Silk Saree', 'Rare double-ikat Patola from Gujarat, heirloom quality.'],
        ['Maheshwari Saree', 'Handwoven Maheshwari with reversible border.'],
      ],
      'Dresses': [
        ['Embroidered Kurti', 'Cotton kurti with delicate Chikankari hand embroidery.'],
        ['Anarkali Suit', 'Flared cotton-silk Anarkali with block-printed dupatta.'],
        ['Handpainted Dupatta', 'Cotton dupatta featuring traditional Madhubani art.'],
        ['Phulkari Suit', 'Punjabi Phulkari hand-embroidered suit piece.'],
        ['Kalamkari Dress', 'Hand-painted Kalamkari fabric with natural dyes.'],
        ['Bandhani Kurti', 'Gujarati Bandhani tie-dye kurti in bright hues.'],
        ['Chanderi Kurta', 'Sheer Chanderi kurta for festive occasions.'],
        ['Ajrakh Tunic', 'Ajrakh block-printed cotton tunic from Kutch.'],
        ['Kantha Stitch Kurti', 'Bengal Kantha embroidered cotton kurti.'],
        ['Dabu Print Dress', 'Rajasthani Dabu mud-resist printed dress.'],
      ],
      'Handicrafts': [
        ['Terracotta Vase', 'Hand-thrown clay vase finished with natural slip.'],
        ['Brass Diya Set', 'Handcrafted brass diyas from Moradabad.'],
        ['Blue Pottery Plate', 'Jaipur blue pottery plate, hand-painted.'],
        ['Pattachitra Painting', 'Traditional Odisha scroll painting on cloth.'],
        ['Dhokra Figurine', 'Lost-wax brass figurine from Bastar.'],
        ['Bamboo Basket', 'Handwoven bamboo basket, eco-friendly.'],
        ['Madhubani Canvas', 'Hand-painted Madhubani art on canvas.'],
        ['Wooden Elephant', 'Hand-carved rosewood elephant from Karnataka.'],
        ['Channapatna Toy', 'Lacquered wooden toy from Karnataka.'],
        ['Bidriware Box', 'Bidri silver inlay metalwork box from Bidar.'],
      ],
      'Jewelry': [
        ['Oxidized Silver Earrings', 'Handcrafted oxidised jhumka earrings.'],
        ['Kundan Necklace', 'Traditional Kundan-set necklace with pearls.'],
        ['Meenakari Bangles', 'Jaipur Meenakari enamel bangles.'],
        ['Terracotta Necklace', 'Handmade clay jewellery with tribal motifs.'],
        ['Dokra Pendant', 'Dokra brass pendant with dhokra craft.'],
        ['Silver Anklets', 'Pure silver anklets with ghungroo bells.'],
        ['Beaded Choker', 'Hand-beaded choker with semi-precious stones.'],
        ['Jadau Ring', 'Traditional Jadau-set ring in gold finish.'],
        ['Thewa Pendant', 'Rajasthani Thewa art pendant in gold on glass.'],
        ['Filigree Earrings', 'Silver filigree earrings from Cuttack.'],
      ],
    };

    final cats = templates.keys.toList();
    final batch = _db.batch();
    int count = 0;

    for (final cat in cats) {
      final tList = templates[cat]!;
      for (int t = 0; t < tList.length; t++) {
        for (int sIdx = 0; sIdx < 3; sIdx++) {
          if (count >= 100) break;
          final seller = sellers[(t * 3 + sIdx) % sellers.length];
          final tpl = tList[t];
          final basePrice = cat == 'Sarees'
              ? 1200 + rng.nextInt(7000)
              : cat == 'Dresses'
                  ? 700 + rng.nextInt(2800)
                  : cat == 'Jewelry'
                      ? 300 + rng.nextInt(4000)
                      : 500 + rng.nextInt(2500);
          final id = const Uuid().v4();
          final imgSeed = 'kalakriti_${id.substring(0, 8)}';
          final rating = 3.8 + rng.nextDouble() * 1.2;
          final ratingCount = 5 + rng.nextInt(80);
          final views = 30 + rng.nextInt(900);

          batch.set(_db.collection('products').doc(id), {
            'id': id,
            'title': tpl[0],
            'description':
                '${tpl[1]} Each piece is unique and takes 5-15 days to make.',
            'descriptionHi': 'हाथ से बनी, पारंपरिक भारतीय शिल्प।',
            'price': basePrice.toDouble(),
            'category': cat,
            'sellerId': seller['id'],
            'sellerName': '${seller['name']}, ${seller['city']}',
            'sellerPhotoUrl': seller['photo'],
            'location': seller['city'],
            'lat': seller['lat'],
            'lng': seller['lng'],
            'deliveryInfo': 'Handcrafted with love · ships in 3-5 days',
            'createdAt': Timestamp.fromDate(
                now.subtract(Duration(days: rng.nextInt(60)))),
            'keywords': _kw(tpl[0], tpl[1]),
            'imageBytes': <String>[],
            'imageUrls': <String>[
              'https://picsum.photos/seed/$imgSeed/800/800',
              'https://picsum.photos/seed/$imgSeed-b/800/800',
              'https://picsum.photos/seed/$imgSeed-c/800/800',
            ],
            'rating': double.parse(rating.toStringAsFixed(1)),
            'ratingCount': ratingCount,
            'views': views,
          });
          count++;
        }
      }
    }
    await batch.commit();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ANIMATIONS
// ═══════════════════════════════════════════════════════════════════════════
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

class ShimmerCard extends StatefulWidget {
  const ShimmerCard({super.key});
  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final v = _c.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment(-1.0 + 2 * v, 0),
                end: Alignment(1.0 + 2 * v, 0),
                colors: <Color>[
                  K.paper,
                  K.gold.withValues(alpha: 0.15),
                  K.paper,
                ],
              ),
            ),
          );
        },
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  DOODLE BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════
class Doodle extends StatelessWidget {
  final Widget child;
  const Doodle({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: _DoodlePainter())),
          child,
        ],
      );
}

class _DoodlePainter extends CustomPainter {
  final _line = Paint()
    ..color = K.maroon.withValues(alpha: 0.06)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  final _gold = Paint()..color = K.gold.withValues(alpha: 0.08);

  @override
  void paint(Canvas c, Size sz) {
    const tile = 160.0;
    final cols = (sz.width / tile).ceil() + 1;
    final rows = (sz.height / tile).ceil() + 1;
    for (int r = 0; r < rows; r++) {
      for (int cc = 0; cc < cols; cc++) {
        final o = Offset(cc * tile, r * tile);
        final m = (r + cc) % 3;
        if (m == 0) {
          _mandala(c, o);
        } else if (m == 1) {
          _paisley(c, o);
        } else {
          _lotus(c, o);
        }
      }
    }
  }

  void _mandala(Canvas c, Offset o) {
    final x = o.dx + 45, y = o.dy + 45;
    c.drawCircle(Offset(x, y), 20, _line);
    c.drawCircle(Offset(x, y), 12, _line);
    c.drawCircle(Offset(x, y), 4, _gold);
    for (int i = 0; i < 12; i++) {
      final a = i * 0.523599;
      final cs = 1 - a * a / 2 + a * a * a * a / 24;
      final sn = a - a * a * a / 6 + a * a * a * a * a / 120;
      c.drawLine(Offset(x + 20 * cs, y + 20 * sn),
          Offset(x + 26 * cs, y + 26 * sn), _line);
    }
  }

  void _paisley(Canvas c, Offset o) {
    final x = o.dx + 40, y = o.dy + 45;
    final p = Path()
      ..moveTo(x, y + 15)
      ..quadraticBezierTo(x - 18, y - 5, x, y - 18)
      ..quadraticBezierTo(x + 18, y - 5, x, y + 15);
    c.drawPath(p, _line);
    c.drawCircle(Offset(x, y - 3), 3, _gold);
  }

  void _lotus(Canvas c, Offset o) {
    final x = o.dx + 40, y = o.dy + 50;
    for (int i = -2; i <= 2; i++) {
      final p = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + i * 8, y - 18, x + i * 12, y);
      c.drawPath(p, _line);
    }
    c.drawCircle(Offset(x, y), 3, _gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  SPLASH
// ═══════════════════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logo;
  late final AnimationController _text;
  late final AnimationController _dots;
  late final AnimationController _ring;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _logo = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _text = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _dots = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _ring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    _fade = CurvedAnimation(parent: _logo, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.45, end: 1.0)
        .animate(CurvedAnimation(parent: _logo, curve: Curves.elasticOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(CurvedAnimation(parent: _text, curve: Curves.easeOutCubic));
    _logo.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _text.forward();
    });
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _logo.dispose();
    _text.dispose();
    _dots.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: K.cream,
        body: Doodle(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildLogo(),
                const SizedBox(height: 44),
                _buildText(),
                const SizedBox(height: 70),
                _buildDots(),
              ],
            ),
          ),
        ),
      );

  Widget _buildLogo() => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _ring,
            builder: (_, _) {
              final v = _ring.value;
              return Container(
                width: 160 + v * 80,
                height: 160 + v * 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: K.gold.withValues(alpha: 0.5 * (1 - v)),
                      width: 2),
                ),
              );
            },
          ),
          FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: <Color>[K.maroon, K.deepMaroon],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: K.maroon.withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_florist, size: 72, color: K.goldLight),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _buildText() => FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: const Column(
            children: <Widget>[
              Text('कलाकृति',
                  style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: K.maroon,
                      letterSpacing: 2)),
              SizedBox(height: 6),
              Text('KALAKRITI',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: K.maroon,
                      letterSpacing: 7)),
              SizedBox(height: 14),
              Text('Where tradition meets expression',
                  style: TextStyle(
                      fontSize: 13,
                      color: K.inkSoft,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      );

  Widget _buildDots() => FadeTransition(
        opacity: _fade,
        child: AnimatedBuilder(
          animation: _dots,
          builder: (_, _) {
            final i = (_dots.value * 3).floor() % 3;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                3,
                (idx) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: idx == i ? 16 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: idx == i ? K.maroon : K.maroon.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ONBOARDING
// ═══════════════════════════════════════════════════════════════════════════
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final pages = <Map<String, dynamic>>[
      {
        'icon': Icons.local_florist,
        'title': prov.t('onboard_1_title'),
        'desc': prov.t('onboard_1_desc'),
        'color': K.maroon,
      },
      {
        'icon': Icons.auto_awesome,
        'title': prov.t('onboard_2_title'),
        'desc': prov.t('onboard_2_desc'),
        'color': K.gold,
      },
      {
        'icon': Icons.balance,
        'title': prov.t('onboard_3_title'),
        'desc': prov.t('onboard_3_desc'),
        'color': K.leaf,
      },
    ];
    return Scaffold(
      backgroundColor: K.cream,
      body: Doodle(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: PageView.builder(
                  controller: _ctrl,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: pages.length,
                  itemBuilder: (_, i) {
                    final p = pages[i];
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          FadeSlideIn(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (p['color'] as Color)
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                    color: p['color'] as Color, width: 2),
                              ),
                              child: Icon(p['icon'] as IconData,
                                  size: 100, color: p['color'] as Color),
                            ),
                          ),
                          const SizedBox(height: 40),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 150),
                            child: Text(p['title'] as String,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: K.maroon)),
                          ),
                          const SizedBox(height: 16),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 250),
                            child: Text(p['desc'] as String,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 15,
                                    color: K.inkSoft,
                                    height: 1.6)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: <Widget>[
                    Row(
                      children: List<Widget>.generate(
                        pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? K.maroon
                                : K.maroon.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await prov.setOnboarded();
                      },
                      child: Text(prov.t('skip'),
                          style: const TextStyle(color: K.inkSoft)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (_page == pages.length - 1) {
                          await prov.setOnboarded();
                        } else {
                          _ctrl.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut);
                        }
                      },
                      child: Text(_page == pages.length - 1
                          ? prov.t('get_started')
                          : prov.t('next')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LOGIN
// ═══════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleBusy = false;
  String? _err;

  Future<void> _googleSignIn() async {
    setState(() {
      _googleBusy = true;
      _err = null;
    });

    final user = await AuthService2.signInWithGoogle();

    if (!mounted) return;
    setState(() => _googleBusy = false);

    if (user == null) {
      setState(() => _err = 'Sign-in cancelled or failed. Try again.');
    }
    // On success, StreamBuilder in _RootGate auto-navigates to Shop
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: K.cream,
        body: Doodle(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // Logo
                    FadeSlideIn(
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: <Color>[K.maroon, K.deepMaroon],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: K.maroon.withValues(alpha: 0.35),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.local_florist,
                            size: 68, color: K.goldLight),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Brand
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 100),
                      child: const Text('कलाकृति',
                          style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.bold,
                              color: K.maroon,
                              letterSpacing: 2)),
                    ),
                    const SizedBox(height: 6),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 150),
                      child: const Text('KALAKRITI',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: K.maroon,
                              letterSpacing: 6)),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 200),
                      child: const Text('Where tradition meets expression',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              color: K.inkSoft,
                              fontStyle: FontStyle.italic)),
                    ),

                    const SizedBox(height: 60),

                    // Welcome text
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 250),
                      child: const Text('Welcome, artisan',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: K.ink)),
                    ),
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 300),
                      child: const Text('Sign in to start selling your craft',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: K.inkSoft)),
                    ),

                    const SizedBox(height: 32),

                    // Google Sign-In button
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 350),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _googleBusy ? null : _googleSignIn,
                          icon: _googleBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: K.maroon),
                                )
                              : const Icon(Icons.g_mobiledata,
                                  size: 32, color: K.maroon),
                          label: Text(
                            _googleBusy
                                ? 'Signing in…'
                                : 'Continue with Google',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 60),
                            foregroundColor: K.maroon,
                            side: BorderSide(
                                color: K.gold.withValues(alpha: 0.6),
                                width: 1.5),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Error box
                    if (_err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_err!,
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.red)),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 40),

                    // Footer note
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 400),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.lock_outline,
                              size: 14, color: K.inkSoft.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Text('Secure sign-in with your Google account',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: K.inkSoft.withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  LOCATION PERMISSION / MAP PICKER SCREENS (NEW)
// ═══════════════════════════════════════════════════════════════════════════

/// A screen that asks for the user's location and shows a map picker.
/// Returns the chosen LatLng via Navigator.pop.
class MapLocationPickerScreen extends StatefulWidget {
  final String? initialAddressLabel;
  final LatLng? initialCenter;
  const MapLocationPickerScreen({
    super.key,
    this.initialAddressLabel,
    this.initialCenter,
  });

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final _ctrl = MapController();
  LatLng? _pin;
  String _label = '';
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCenter != null) {
      _pin = widget.initialCenter;
      _label = widget.initialAddressLabel ??
          LocationService.nearestCity(_pin!.latitude, _pin!.longitude);
    }
    _tryAuto();
  }

  Future<void> _tryAuto() async {
    if (_pin != null) return;
    setState(() => _locating = true);
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos != null) {
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _pin = ll;
        _label = LocationService.nearestCity(ll.latitude, ll.longitude);
      });
      _ctrl.move(ll, 12);
    }
  }

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos != null) {
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _pin = ll;
        _label = LocationService.nearestCity(ll.latitude, ll.longitude);
      });
      _ctrl.move(ll, 14);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location unavailable')),
      );
    }
  }

  void _confirm() {
    if (_pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap the map to pin a location')),
      );
      return;
    }
    Navigator.pop(context, {'lat': _pin!.latitude, 'lng': _pin!.longitude, 'label': _label});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Pick Your Location'),
          backgroundColor: K.maroon,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _ctrl,
              options: MapOptions(
                initialCenter:
                    widget.initialCenter ?? const LatLng(22.5, 78.9),
                initialZoom: widget.initialCenter != null ? 12 : 4.5,
                onTap: (_, ll) {
                  setState(() {
                    _pin = ll;
                    _label = LocationService.nearestCity(ll.latitude, ll.longitude);
                  });
                },
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kalakriti.app',
                ),
                if (_pin != null)
                  MarkerLayer(
                    markers: <Marker>[
                      Marker(
                        point: _pin!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.location_on,
                            color: K.maroon, size: 44),
                      ),
                    ],
                  ),
              ],
            ),
            if (_locating)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: K.maroon)),
                        SizedBox(width: 10),
                        Text('Locating…'),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _pin == null
                            ? 'Tap anywhere on the map to pin'
                            : '📍 $_label',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: K.maroon,
                            fontSize: 14),
                      ),
                      if (_pin != null)
                        Text(
                          'Lat: ${_pin!.latitude.toStringAsFixed(4)} · Lng: ${_pin!.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                              fontSize: 11, color: K.inkSoft),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.my_location, size: 16),
                              label: const Text('My Location',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: _myLocation,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Confirm',
                                  style: TextStyle(fontSize: 12)),
                              onPressed: _confirm,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Wraps product listing to ensure the seller picks a location first.
class SetLocationPromptScreen extends StatefulWidget {
  const SetLocationPromptScreen({super.key});
  @override
  State<SetLocationPromptScreen> createState() =>
      _SetLocationPromptScreenState();
}

class _SetLocationPromptScreenState extends State<SetLocationPromptScreen> {
  bool _busy = false;

  Future<void> _pick() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const MapLocationPickerScreen(),
      ),
    );
    if (result != null && mounted) {
      final prov = Provider.of<ProductProvider>(context, listen: false);
      await prov.setUserLocation(
          result['lat'] as double, result['lng'] as double);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location set!'),
              backgroundColor: K.leaf),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _auto() async {
    setState(() => _busy = true);
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _busy = false);
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }
    final prov = Provider.of<ProductProvider>(context, listen: false);
    await prov.setUserLocation(pos.latitude, pos.longitude);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location set!'), backgroundColor: K.leaf),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: K.cream,
        appBar: AppBar(
          title: const Text('Set Your Location'),
          backgroundColor: K.maroon,
          foregroundColor: Colors.white,
        ),
        body: Doodle(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: K.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on,
                      size: 72, color: K.maroon),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Set Your Location',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: K.maroon),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pin your shop location so buyers see exact distance and delivery time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: K.inkSoft, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.my_location),
                    label: const Text('Use My Location',
                        style: TextStyle(fontSize: 15)),
                    onPressed: _busy ? null : _auto,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 54)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pick on Map',
                        style: TextStyle(fontSize: 15)),
                    onPressed: _pick,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 54)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  SETTINGS
// ═══════════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _name;
  late TextEditingController _bio;
  Uint8List? _newPhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final me = Provider.of<ProductProvider>(context, listen: false).me;
    _name = TextEditingController(text: me?.displayName ?? '');
    _bio = TextEditingController(text: me?.bio ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 500);
    if (f != null) {
      final b = await f.readAsBytes();
      setState(() => _newPhoto = b);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prov = Provider.of<ProductProvider>(context, listen: false);
    String? photoUrl;
    if (_newPhoto != null) {
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final ref = FirebaseStorage.instance.ref('profile_pics/$uid.jpg');
        await ref.putData(_newPhoto!);
        photoUrl = await ref.getDownloadURL();
      } catch (_) {}
    }
    await prov.updateProfile(
      displayName: _name.text.trim(),
      bio: _bio.text.trim(),
      photoUrl: photoUrl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(prov.t('saved')), backgroundColor: K.leaf),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final me = prov.me;
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('settings')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    children: <Widget>[
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: K.gold.withValues(alpha: 0.2),
                          border: Border.all(color: K.gold, width: 3),
                          image: _newPhoto != null
                              ? DecorationImage(
                                  image: MemoryImage(_newPhoto!),
                                  fit: BoxFit.cover)
                              : (me?.photoUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(me!.photoUrl!),
                                      fit: BoxFit.cover)
                                  : null),
                        ),
                        child: (_newPhoto == null && me?.photoUrl == null)
                            ? const Icon(Icons.person,
                                size: 56, color: K.maroon)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                              color: K.maroon, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _lbl(prov.t('display_name')),
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: 'e.g. Meera Devi'),
              ),
              const SizedBox(height: 18),
              _lbl(prov.t('bio')),
              TextField(
                controller: _bio,
                maxLines: 3,
                decoration: InputDecoration(hintText: prov.t('bio_hint')),
              ),
              const SizedBox(height: 18),
              _lbl('Your Location'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: K.gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_on, color: K.maroon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        prov.hasUserLocation
                            ? '📍 ${prov.userCity}'
                            : 'Location not set',
                        style: const TextStyle(
                            color: K.ink, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetLocationPromptScreen(),
                        ),
                      ),
                      child: Text(prov.hasUserLocation ? 'Change' : 'Set'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const LanguageSwitcherCard(),
              const SizedBox(height: 18),
              _lbl(prov.t('account')),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: K.gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.email_outlined, color: K.maroon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AuthService.currentUser?.email ?? '',
                        style: const TextStyle(color: K.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving
                    ? prov.t('loading')
                    : prov.t('save_changes')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final c = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: K.cream,
                      title: Text(prov.t('logout')),
                      content: const Text('Are you sure?'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(prov.t('cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (c == true) await AuthService2.signOut();
                },
                icon: const Icon(Icons.logout),
                label: Text(prov.t('logout')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: K.maroon,
                  side: const BorderSide(color: K.maroon),
                  minimumSize: const Size(0, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: K.maroon, fontSize: 14)),
      );


}

// ═══════════════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════════════
Widget productImg(Product p, {double? h, BoxFit fit = BoxFit.cover}) {
  if (p.images.isNotEmpty) {
    return Image.memory(p.images.first,
        height: h, width: double.infinity, fit: fit, gaplessPlayback: true);
  }
  if (p.imageUrls.isNotEmpty) {
    return Image.network(
      p.imageUrls.first,
      height: h,
      width: double.infinity,
      fit: fit,
      errorBuilder: (_, _, _) => _colorTile(p, h),
      loadingBuilder: (_, child, prog) =>
          prog == null ? child : _colorTile(p, h),
    );
  }
  return _colorTile(p, h);
}

Widget _colorTile(Product p, double? h) {
  final col = colorFor(p.category);
  return Container(
    height: h,
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          col.withValues(alpha: 0.4),
          col.withValues(alpha: 0.85),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Icon(iconFor(p.category),
          size: h != null ? h * 0.35 : 64, color: Colors.white),
    ),
  );
}

class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  final bool showNumber;
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.showNumber = true,
  });

  @override
  Widget build(BuildContext context) {
    final full = rating.floor();
    final half = (rating - full) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++)
          Icon(
            i < full
                ? Icons.star
                : (i == full && half ? Icons.star_half : Icons.star_border),
            size: size,
            color: K.gold,
          ),
        if (showNumber) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
                fontSize: size * 0.85,
                color: K.inkSoft,
                fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

/// A compact distance + delivery info chip used in product cards.
class DistanceChip extends StatelessWidget {
  final double km;
  final bool compact;
  const DistanceChip({super.key, required this.km, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final label = km < 1
        ? '<1 km'
        : km < 10
            ? '${km.toStringAsFixed(1)} km'
            : '${km.toStringAsFixed(0)} km';
    final days = LocationService.deliveryDaysFor(km);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: K.leaf.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: K.leaf.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.near_me, size: 10, color: K.leaf),
          const SizedBox(width: 3),
          Text(
            '$label · ${days}d',
            style: TextStyle(
                color: K.leaf,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRODUCT CAROUSEL
// ═══════════════════════════════════════════════════════════════════════════
class ProductCarousel extends StatefulWidget {
  final Product product;
  final double height;
  const ProductCarousel({super.key, required this.product, this.height = 320});

  @override
  State<ProductCarousel> createState() => _ProductCarouselState();
}

class _ProductCarouselState extends State<ProductCarousel> {
  int _page = 0;
  final _ctrl = PageController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.product.imageUrls;
    final bytes = widget.product.images;

    if (urls.isEmpty && bytes.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: productImg(widget.product, h: widget.height),
      );
    }

    final count = urls.isNotEmpty ? urls.length : bytes.length;
    final dots = <Widget>[];
    for (int i = 0; i < count; i++) {
      dots.add(AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: i == _page ? 20 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: i == _page ? K.gold : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
          ],
        ),
      ));
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: count,
            itemBuilder: (_, i) => urls.isNotEmpty
                ? Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, _, _) =>
                        productImg(widget.product, h: widget.height),
                  )
                : Image.memory(
                    bytes[i],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    gaplessPlayback: true,
                  ),
          ),
          if (count > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dots,
              ),
            ),
          if (count > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_page + 1}/$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HOME
// ═══════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _q = '';
  String _cat = 'All';
  bool _nearMe = false;
  bool _sortByDistance = false;

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    var feed = prov.getRecommendedFeed();
    if (_cat != 'All') {
      feed = feed.where((p) => p.category == _cat).toList();
    }
    if (_nearMe && prov.hasUserLocation) {
      feed = feed.where((p) => prov.distanceToProduct(p) <= 300).toList();
    }
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      feed = feed
          .where((p) =>
              p.title.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q) ||
              p.sellerName.toLowerCase().contains(q) ||
              p.keywords.any((k) => k.contains(q)))
          .toList();
    }
    if (_sortByDistance && prov.hasUserLocation) {
      feed = prov.sortedByDistance(feed);
    }

    return CustomScrollView(
      slivers: <Widget>[
        // location banner
        if (!prov.hasUserLocation)
          SliverToBoxAdapter(
            child: FadeSlideIn(
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: K.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: K.maroon),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_off, color: K.maroon, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Set your location to see delivery ETA',
                          style: TextStyle(
                              fontSize: 12,
                              color: K.maroon,
                              fontWeight: FontWeight.w500)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetLocationPromptScreen(),
                        ),
                      ),
                      child: const Text('Set'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: FadeSlideIn(
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: K.leaf.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: K.leaf.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_on, color: K.leaf, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Delivering to ${prov.userCity}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: K.leaf,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SetLocationPromptScreen(),
                        ),
                      ),
                      child: const Text('Change',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // search
        SliverToBoxAdapter(
          child: FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: prov.t('search_hint'),
                  prefixIcon: const Icon(Icons.search, color: K.maroon),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: K.paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide:
                        BorderSide(color: K.gold.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide:
                        BorderSide(color: K.gold.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide:
                        const BorderSide(color: K.maroon, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),

        // categories
        SliverToBoxAdapter(
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: kCategories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = kCategories[i];
                  final sel = _cat == c;
                  return ChoiceChip(
                    label: Text(c),
                    selected: sel,
                    selectedColor: K.maroon,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : K.maroon,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    backgroundColor: K.paper,
                    side: BorderSide(color: K.gold.withValues(alpha: 0.5)),
                    onSelected: (_) => setState(() => _cat = c),
                  );
                },
              ),
            ),
          ),
        ),

        // near me / sort toggle
        SliverToBoxAdapter(
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: <Widget>[
                  FilterChip(
                    avatar: Icon(
                      Icons.near_me,
                      size: 16,
                      color: _nearMe ? Colors.white : K.maroon,
                    ),
                    label: const Text('Near me',
                        style: TextStyle(fontSize: 12)),
                    selected: _nearMe,
                    selectedColor: K.maroon,
                    labelStyle: TextStyle(
                        color: _nearMe ? Colors.white : K.maroon,
                        fontWeight: FontWeight.w600),
                    backgroundColor: K.paper,
                    onSelected: (v) {
                      if (!prov.hasUserLocation) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SetLocationPromptScreen(),
                          ),
                        );
                        return;
                      }
                      setState(() => _nearMe = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: Icon(
                      Icons.sort,
                      size: 16,
                      color: _sortByDistance ? Colors.white : K.maroon,
                    ),
                    label: const Text('Nearest first',
                        style: TextStyle(fontSize: 12)),
                    selected: _sortByDistance,
                    selectedColor: K.maroon,
                    labelStyle: TextStyle(
                        color: _sortByDistance ? Colors.white : K.maroon,
                        fontWeight: FontWeight.w600),
                    backgroundColor: K.paper,
                    onSelected: (v) {
                      if (!prov.hasUserLocation) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SetLocationPromptScreen(),
                          ),
                        );
                        return;
                      }
                      setState(() => _sortByDistance = v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // fair feed banner
        SliverToBoxAdapter(
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    K.gold.withValues(alpha: 0.18),
                    K.gold.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: K.gold.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.balance, color: K.maroon, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prov.t('fair_feed'),
                      style: const TextStyle(
                          fontSize: 12,
                          color: K.maroon,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: TrendingRow()),
        const SliverToBoxAdapter(child: RecentlyViewedRow()),

        if (!prov.loaded)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, _) => const ShimmerCard(),
                childCount: 6,
              ),
            ),
          )
        else if (feed.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.search_off,
                        size: 64, color: K.maroon.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(prov.t('no_match'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, color: K.inkSoft)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.60,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => FadeSlideIn(
                  key: ValueKey(feed[i].id),
                  delay: Duration(milliseconds: (i * 40).clamp(0, 400)),
                  child: ProductCard(product: feed[i]),
                ),
                childCount: feed.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PRODUCT CARD
// ═══════════════════════════════════════════════════════════════════════════
class ProductCard extends StatelessWidget {
  final Product product;
  final bool useHero;
  const ProductCard({super.key, required this.product, this.useHero = true});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final w = prov.isWished(product.id);
    final km = prov.distanceToProduct(product);
    final showDist = prov.hasUserLocation && product.hasLocation;

    return Container(
      decoration: BoxDecoration(
        color: K.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.gold.withValues(alpha: 0.35)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: K.maroon.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            prov.trackView(product.id);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailScreen(product: product),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    if (useHero)
                      Hero(tag: 'p-${product.id}', child: productImg(product))
                    else
                      productImg(product),
                    if (product.isNew)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: K.maroon,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                  color: K.maroon.withValues(alpha: 0.3),
                                  blurRadius: 6),
                            ],
                          ),
                          child: Text(
                            prov.t('new_badge'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.95),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => prov.toggleWish(product.id),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                w ? Icons.favorite : Icons.favorite_border,
                                key: ValueKey(w),
                                size: 18,
                                color: w ? K.maroon : K.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: K.maroon.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.category,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: K.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.sellerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          color: K.inkSoft.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic),
                    ),
                    if (showDist)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DistanceChip(km: km, compact: true),
                      ),
                    if (product.ratingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: RatingStars(rating: product.rating, size: 11),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            '₹${product.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 16,
                                color: K.maroon,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: K.maroon,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              prov.addToCart(product.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${product.title} ${prov.t('added_to_cart')}'),
                                  backgroundColor: K.leaf,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.add,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TRENDING / RECENTLY VIEWED
// ═══════════════════════════════════════════════════════════════════════════
class TrendingRow extends StatelessWidget {
  const TrendingRow({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final list = prov.trending;
    if (list.isEmpty) return const SizedBox.shrink();
    return FadeSlideIn(
      delay: const Duration(milliseconds: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: <Widget>[
                Container(width: 4, height: 16, color: K.gold),
                const SizedBox(width: 8),
                Text(prov.t('trending'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: K.maroon)),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 140,
                child: ProductCard(product: list[i], useHero: false),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class RecentlyViewedRow extends StatelessWidget {
  const RecentlyViewedRow({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final list = prov.recentlyViewed
        .map((id) => prov.products.where((p) => p.id == id).toList())
        .where((l) => l.isNotEmpty)
        .map((l) => l.first)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return FadeSlideIn(
      delay: const Duration(milliseconds: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: <Widget>[
                Container(width: 4, height: 16, color: K.gold),
                const SizedBox(width: 8),
                Text(prov.t('recently_viewed'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: K.maroon)),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 140,
                child: ProductCard(product: list[i], useHero: false),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DETAIL
// ═══════════════════════════════════════════════════════════════════════════
class DetailScreen extends StatefulWidget {
  final Product product;
  const DetailScreen({super.key, required this.product});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _db = FirebaseFirestore.instance;
  List<Review> _reviews = [];
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await _db
          .collection('reviews')
          .where('productId', isEqualTo: widget.product.id)
          .limit(20)
          .get();
      if (!mounted) return;
      setState(() {
        _reviews = snap.docs.map((d) => Review.fromMap(d.data())).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _loadingReviews = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final product = widget.product;
    final w = prov.isWished(product.id);
    final km = prov.distanceToProduct(product);
    final hasRealDistance = prov.hasUserLocation && product.hasLocation;
    final days = LocationService.deliveryDaysFor(km);
    final fee = LocationService.deliveryFeeFor(km);
    final window = LocationService.deliveryWindow(km);

    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('product')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final txt = '${product.title} — '
                  '₹${product.price.toStringAsFixed(0)}\n'
                  'by ${product.sellerName}\n\n${product.description}\n\n'
                  '${product.location.isNotEmpty ? "📍 ${product.location}\n" : ""}'
                  '\nOn Kalakriti';
              Clipboard.setData(ClipboardData(text: txt));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(prov.t('copied')),
                    backgroundColor: K.leaf),
              );
            },
          ),
          IconButton(
            icon: Icon(w ? Icons.favorite : Icons.favorite_border),
            onPressed: () => prov.toggleWish(product.id),
          ),
        ],
      ),
      body: Doodle(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Hero(
                tag: 'p-${product.id}',
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () {
                      if (product.images.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(
                                images: product.images, initialIndex: 0),
                          ),
                        );
                      }
                    },
                    child: ProductCarousel(
                        product: product, height: 340),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: K.maroon.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: K.maroon.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            product.category,
                            style: const TextStyle(
                                color: K.maroon,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        if (product.isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: K.gold,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              prov.t('new_badge'),
                              style: const TextStyle(
                                  color: K.maroon,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      product.title,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: K.maroon,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 8),
                    if (product.ratingCount > 0)
                      Row(
                        children: <Widget>[
                          RatingStars(rating: product.rating, size: 16),
                          const SizedBox(width: 6),
                          Text('(${product.ratingCount})',
                              style: const TextStyle(
                                  fontSize: 12, color: K.inkSoft)),
                          const SizedBox(width: 12),
                          const Icon(Icons.visibility_outlined,
                              size: 14, color: K.inkSoft),
                          const SizedBox(width: 4),
                          Text('${product.views} views',
                              style: const TextStyle(
                                  fontSize: 12, color: K.inkSoft)),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.storefront, size: 16),
                            label: Text(prov.t('seller_products'),
                                style: const TextStyle(fontSize: 12)),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SellerProfileScreen(
                                  sellerId: product.sellerId,
                                  sellerName: product.sellerName,
                                ),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 16),
                            label: const Text('Chat',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatWithSellerScreen(
                                  sellerId: product.sellerId,
                                  sellerName: product.sellerName,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 40)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '₹${product.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 30,
                          color: K.maroon,
                          fontWeight: FontWeight.bold),
                    ),

                    // ─── DELIVERY ETA PANEL ───
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: K.leaf.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: K.leaf.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Icon(Icons.local_shipping,
                                  size: 18, color: K.leaf),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${prov.t('delivery_eta')}: $window',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: K.leaf,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.near_me,
                                  size: 14, color: K.inkSoft),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  hasRealDistance
                                      ? '${km.toStringAsFixed(0)} km ${prov.t('from_you')} · $days day${days != 1 ? 's' : ''} transit'
                                      : 'Set your location for exact ETA',
                                  style: const TextStyle(
                                      fontSize: 12, color: K.inkSoft),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.currency_rupee,
                                  size: 14, color: K.inkSoft),
                              const SizedBox(width: 6),
                              Text(
                                fee == 0
                                    ? prov.t('free_delivery')
                                    : '${prov.t('delivery_charge')}: ₹${fee.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: fee == 0 ? K.leaf : K.inkSoft,
                                  fontWeight: fee == 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          if (product.location.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 6),
                            Row(
                              children: <Widget>[
                                const Icon(Icons.store,
                                    size: 14, color: K.inkSoft),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${prov.t('shipping_from')}: ${product.location}',
                                    style: const TextStyle(
                                        fontSize: 12, color: K.inkSoft),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (!prov.hasUserLocation)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SetLocationPromptScreen(),
                                  ),
                                ),
                                icon: const Icon(Icons.location_on, size: 16),
                                label: const Text('Set your location'),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    _div(prov.t('description')),
                    Text(
                      product.description,
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: K.ink),
                    ),
                    if (product.descriptionHi.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _div('हिन्दी विवरण'),
                      Text(
                        product.descriptionHi,
                        style: const TextStyle(
                            fontSize: 14, height: 1.6, color: K.ink),
                      ),
                    ],
                    if (product.deliveryInfo.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _div(prov.t('delivery')),
                      Text(
                        product.deliveryInfo,
                        style: const TextStyle(
                            fontSize: 14, height: 1.6, color: K.ink),
                      ),
                    ],
                    if (product.keywords.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      _div(prov.t('tags')),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: product.keywords
                            .map((k) => Chip(
                                  label: Text(k,
                                      style: const TextStyle(fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: K.paper,
                                  side: BorderSide(
                                      color:
                                          K.gold.withValues(alpha: 0.5)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _div('${prov.t('reviews')} (${_reviews.length})'),
                    const SizedBox(height: 8),
                    if (_loadingReviews)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(color: K.maroon),
                        ),
                      )
                    else if (_reviews.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: K.paper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: K.gold.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.rate_review_outlined,
                                color: K.maroon.withValues(alpha: 0.6)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                prov.t('no_reviews'),
                                style: const TextStyle(
                                    color: K.inkSoft, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _reviews
                            .take(5)
                            .map((r) => Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: K.paper,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: K.gold
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: K.gold
                                                .withValues(alpha: 0.4),
                                            child: Text(
                                              r.userName.isNotEmpty
                                                  ? r.userName[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                  color: K.maroon,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              r.userName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: K.ink),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          RatingStars(
                                              rating: r.rating,
                                              size: 12,
                                              showNumber: false),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        r.text,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: K.ink,
                                            height: 1.4),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                WriteReviewScreen(productId: product.id),
                          ),
                        );
                        _loadReviews();
                      },
                      icon: const Icon(Icons.rate_review),
                      label: Text(prov.t('write_review')),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.paper,
            border: Border(
                top: BorderSide(color: K.gold.withValues(alpha: 0.4))),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(prov.t('add_to_cart')),
                  onPressed: () {
                    prov.addToCart(product.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(prov.t('added_to_cart')),
                          backgroundColor: K.leaf),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on),
                  label: Text(prov.t('buy_now')),
                  onPressed: () {
                    prov.addToCart(product.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CheckoutScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _div(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            Container(width: 4, height: 16, color: K.gold),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: K.maroon)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  IMAGE VIEWER
// ═══════════════════════════════════════════════════════════════════════════
class ImageViewerScreen extends StatefulWidget {
  final List<Uint8List> images;
  final int initialIndex;
  const ImageViewerScreen(
      {super.key, required this.images, this.initialIndex = 0});
  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _ctrl;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            '${_page + 1} / ${widget.images.length}',
            style: const TextStyle(fontSize: 15),
          ),
        ),
        body: PageView.builder(
          controller: _ctrl,
          onPageChanged: (i) => setState(() => _page = i),
          itemCount: widget.images.length,
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.memory(widget.images[i], fit: BoxFit.contain),
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  WRITE REVIEW
// ═══════════════════════════════════════════════════════════════════════════
class WriteReviewScreen extends StatefulWidget {
  final String productId;
  const WriteReviewScreen({super.key, required this.productId});
  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  double _rating = 5;
  final _txt = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _txt.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_txt.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a review')),
      );
      return;
    }
    setState(() => _busy = true);
    final prov = Provider.of<ProductProvider>(context, listen: false);
    final user = AuthService.currentUser;
    final r = Review(
      id: const Uuid().v4(),
      productId: widget.productId,
      userId: user?.uid ?? 'anon',
      userName: prov.currentUserName,
      rating: _rating,
      text: _txt.text.trim(),
      createdAt: DateTime.now(),
    );
    try {
      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(r.id)
          .set(r.toMap());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(prov.t('review_added')), backgroundColor: K.leaf),
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('write_review')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(prov.t('rating'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: K.maroon)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    iconSize: 40,
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: K.gold,
                    ),
                    onPressed: () => setState(() => _rating = i + 1.0),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Text(prov.t('your_review'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: K.maroon)),
              const SizedBox(height: 8),
              TextField(
                controller: _txt,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: 'Share your experience…',
                  filled: true,
                  fillColor: K.paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: K.gold.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(prov.t('submit_review')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SELLER PROFILE
// ═══════════════════════════════════════════════════════════════════════════
class SellerProfileScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  const SellerProfileScreen(
      {super.key, required this.sellerId, required this.sellerName});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final items = prov.productsBySeller(sellerId);
    final isFriend = prov.isFriend(sellerId);
    final pending = prov.hasSentRequest(sellerId);
    final photo = items.isNotEmpty ? items.first.sellerPhotoUrl : '';
    final city = items.isNotEmpty ? items.first.location : '';
    final avgRating = items.isEmpty
        ? 0.0
        : items.map((p) => p.rating).reduce((a, b) => a + b) / items.length;

    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(sellerName.split(',').first),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: FadeSlideIn(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[K.maroon, K.deepMaroon],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: K.maroon.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: K.gold,
                            backgroundImage:
                                photo.isNotEmpty ? NetworkImage(photo) : null,
                            child: photo.isEmpty
                                ? const Icon(Icons.person,
                                    size: 32, color: K.maroon)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  sellerName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                if (city.isNotEmpty)
                                  Row(
                                    children: <Widget>[
                                      const Icon(Icons.location_on,
                                          size: 12, color: K.goldLight),
                                      const SizedBox(width: 4),
                                      Text(
                                        city,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.star,
                                        size: 14, color: K.gold),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${avgRating.toStringAsFixed(1)} · '
                                      '${items.length} listing${items.length != 1 ? 's' : ''}',
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(
                                isFriend
                                    ? Icons.people
                                    : pending
                                        ? Icons.hourglass_top
                                        : Icons.person_add_alt,
                                size: 16,
                              ),
                              label: Text(
                                isFriend
                                    ? 'Friends'
                                    : pending
                                        ? 'Requested'
                                        : 'Add Friend',
                                style: const TextStyle(fontSize: 13),
                              ),
                              onPressed: isFriend
                                  ? () => prov.removeFriend(sellerId)
                                  : pending
                                      ? () => prov
                                          .cancelFriendRequest(sellerId)
                                      : () {
                                          prov.sendFriendRequest(sellerId);
                                          Future.delayed(
                                            const Duration(seconds: 3),
                                            () =>
                                                prov.acceptFriend(sellerId),
                                          );
                                        },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: 0.5)),
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.chat_bubble_outline,
                                  size: 16),
                              label: const Text('Chat',
                                  style: TextStyle(fontSize: 13)),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatWithSellerScreen(
                                    sellerId: sellerId,
                                    sellerName: sellerName,
                                  ),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: K.gold,
                                foregroundColor: K.maroon,
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Their Crafts',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: K.maroon)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.60,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ProductCard(product: items[i]),
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FRIENDS SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final list = prov.friendList;
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: const Text('My Artisan Friends'),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.people_outline,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No friends yet.\nTap a seller profile to add.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: K.inkSoft, height: 1.5),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final f = list[i];
                  final photoStr = f['photo'].toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: K.paper,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: K.gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: K.gold.withValues(alpha: 0.3),
                          backgroundImage: photoStr.isNotEmpty
                              ? NetworkImage(photoStr)
                              : null,
                          child: photoStr.isEmpty
                              ? const Icon(Icons.person, color: K.maroon)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                f['name'].toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: K.ink,
                                    fontSize: 15),
                              ),
                              Text(
                                '${f['city']} · ${f['products']} listings',
                                style: const TextStyle(
                                    fontSize: 12, color: K.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline,
                              color: K.maroon),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatWithSellerScreen(
                                sellerId: f['id'].toString(),
                                sellerName: f['name'].toString(),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_remove_outlined,
                              color: K.maroon),
                          onPressed: () =>
                              prov.removeFriend(f['id'].toString()),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INDIA MAP
// ═══════════════════════════════════════════════════════════════════════════
class CraftMarker {
  final String name;
  final String city;
  final String craft;
  final double lat;
  final double lng;
  const CraftMarker(this.name, this.city, this.craft, this.lat, this.lng);
}

const kCraftMarkers = <CraftMarker>[
  CraftMarker('Meera Devi', 'Varanasi, UP', 'Banarasi Weaving', 25.3176, 82.9739),
  CraftMarker('Ravi Kumar', 'Pochampally, TS', 'Ikat Weaving', 17.5626, 78.7000),
  CraftMarker('Lakshmi Weaves', 'Kanchipuram, TN', 'Kanjivaram Silk', 12.8342, 79.7036),
  CraftMarker('Anita Crafts', 'Moradabad, UP', 'Brass Work', 28.8386, 78.7733),
  CraftMarker('Jaipur Arts', 'Jaipur, RJ', 'Bandhani & Jewelry', 26.9124, 75.7873),
  CraftMarker('Bengal Crafts', 'Kolkata, WB', 'Kantha & Terracotta', 22.5726, 88.3639),
  CraftMarker('Gujarat Weaves', 'Bhuj, GJ', 'Bandhani', 23.2420, 69.6669),
  CraftMarker('Odisha Ikat', 'Sambalpur, OD', 'Ikat', 21.4669, 83.9812),
  CraftMarker('Chanderi Looms', 'Chanderi, MP', 'Chanderi Silk', 24.7138, 78.1372),
  CraftMarker('Kerala Crafts', 'Kochi, KL', 'Coir & Brass', 9.9312, 76.2673),
  CraftMarker('Punjab Handlooms', 'Amritsar, PB', 'Phulkari', 31.6340, 74.8723),
  CraftMarker('Kashmir Shawls', 'Srinagar, JK', 'Pashmina', 34.0837, 74.7973),
];

class IndiaMapScreen extends StatefulWidget {
  const IndiaMapScreen({super.key});
  @override
  State<IndiaMapScreen> createState() => _IndiaMapScreenState();
}

class _IndiaMapScreenState extends State<IndiaMapScreen> {
  final _ctrl = MapController();
  CraftMarker? _selected;

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artisan Map of India'),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: <Widget>[
          FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: const LatLng(22.5, 78.9),
              initialZoom: 4.5,
              minZoom: 3,
              maxZoom: 18,
              onTap: (_, _) => setState(() => _selected = null),
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kalakriti.app',
              ),
              if (prov.hasUserLocation)
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: LatLng(prov.userLat, prov.userLng),
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: K.leaf,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.person_pin_circle,
                            color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: kCraftMarkers
                    .map((m) => Marker(
                          point: LatLng(m.lat, m.lng),
                          width: 46,
                          height: 46,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selected = m),
                            child: Container(
                              decoration: BoxDecoration(
                                color: K.maroon,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: K.gold, width: 2),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 6,
                                      offset: Offset(0, 2)),
                                ],
                              ),
                              child: const Icon(Icons.local_florist,
                                  color: K.goldLight, size: 22),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: K.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: K.gold),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black26, blurRadius: 10),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                          color: K.gold, shape: BoxShape.circle),
                      child:
                          const Icon(Icons.storefront, color: K.maroon),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_selected!.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: K.maroon)),
                          Text(_selected!.craft,
                              style: const TextStyle(
                                  fontSize: 12, color: K.inkSoft)),
                          Text('📍 ${_selected!.city}',
                              style: const TextStyle(
                                  fontSize: 11, color: K.leaf)),
                          if (prov.hasUserLocation)
                            Text(
                              '${LocationService.distanceKm(prov.userLat, prov.userLng, _selected!.lat, _selected!.lng).toStringAsFixed(0)} km ${prov.t('away')}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: K.maroon,
                                  fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _selected = null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K.gold,
        onPressed: () => _ctrl.move(const LatLng(22.5, 78.9), 4.5),
        child: const Icon(Icons.my_location, color: K.maroon),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CALENDAR
// ═══════════════════════════════════════════════════════════════════════════
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  final Map<String, Map<String, String>> _events = {
    '2026-10-20': {'title': 'Diwali Sale Prep', 'icon': '🪔'},
    '2026-11-01': {'title': 'Diwali', 'icon': '🎆'},
    '2026-12-25': {'title': 'Christmas Market', 'icon': '🎄'},
    '2027-01-14': {'title': 'Pongal / Makar Sankranti', 'icon': '🌾'},
    '2027-03-08': {'title': 'Holi', 'icon': '🎨'},
    '2027-04-14': {'title': 'Baisakhi', 'icon': '🌾'},
    '2027-08-15': {'title': 'Independence Day', 'icon': '🇮🇳'},
  };

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final events = _events[_key(_selected ?? _focused)];
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('calendar')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: K.paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: K.gold),
            ),
            child: TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focused,
              calendarFormat: _format,
              selectedDayPredicate: (d) => isSameDay(_selected, d),
              onDaySelected: (sel, foc) => setState(() {
                _selected = sel;
                _focused = foc;
              }),
              onFormatChanged: (f) => setState(() => _format = f),
              onPageChanged: (f) => setState(() => _focused = f),
              eventLoader: (d) => _events.containsKey(_key(d))
                  ? <Object>[_events[_key(d)]!]
                  : <Object>[],
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(
                    color: K.gold, shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(
                    color: K.maroon, shape: BoxShape.circle),
                markerDecoration: BoxDecoration(
                    color: K.leaf, shape: BoxShape.circle),
              ),
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  color: K.maroon,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                formatButtonTextStyle: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selected == null
                    ? 'Pick a date'
                    : 'Events on ${_selected!.day}/${_selected!.month}/${_selected!.year}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: K.maroon,
                    fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: events == null
                ? Center(
                    child: Text(prov.t('no_events'),
                        style: const TextStyle(color: K.inkSoft)),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: K.paper,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: K.gold),
                        ),
                        child: Row(
                          children: <Widget>[
                            Text(events['icon']!,
                                style: const TextStyle(fontSize: 32)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(events['title']!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: K.maroon,
                                          fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(prov.t('festival_plan'),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: K.inkSoft,
                                          height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ABOUT / HELP / COUPONS / NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('about')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: <Color>[K.maroon, K.deepMaroon]),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 24,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.local_florist,
                    size: 60, color: K.goldLight),
              ),
              const SizedBox(height: 20),
              const Text('कलाकृति',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: K.maroon)),
              const SizedBox(height: 4),
              const Text('KALAKRITI',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: K.maroon,
                      letterSpacing: 6)),
              const SizedBox(height: 8),
              Text(prov.t('tagline'),
                  style: const TextStyle(
                      fontSize: 14,
                      color: K.inkSoft,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: K.paper,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: K.gold.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  'Kalakriti is a fair marketplace for Indian artisans. '
                  'Every seller gets equal visibility — no paid boosts, '
                  'no hidden algorithms. Powered by Gemini AI to help '
                  'artisans describe, price and sell their craft.',
                  style:
                      TextStyle(fontSize: 14, color: K.ink, height: 1.7),
                ),
              ),
              const SizedBox(height: 30),
              const Text('Version 21.0.0',
                  style: TextStyle(fontSize: 12, color: K.inkSoft)),
              const SizedBox(height: 6),
              const Text('Made with ❤️ in India',
                  style: TextStyle(fontSize: 12, color: K.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    const faqs = <Map<String, String>>[
      {
        'q': 'How do I list a product?',
        'a':
            'Tap Upload tab, add photos, let AI auto-fill or type manually, then publish. You will be asked to pin your location on a map first.',
      },
      {
        'q': 'How does the location & delivery work?',
        'a':
            'You set your location once. Every product you list is pinned with its map coordinates. Buyers see the exact km distance and estimated delivery days automatically.',
      },
      {
        'q': 'How does AI pricing work?',
        'a':
            'Our AI analyzes your image and description, then suggests a fair market range.',
      },
      {
        'q': 'Can I speak my listing?',
        'a':
            'Yes! Tap the mic icon next to the description to dictate in Telugu, Hindi, or English.',
      },
      {
        'q': 'How is shipping calculated?',
        'a':
            'Distance-based: 0-100 km free, 100-500 km ₹40, 500-1200 km ₹80, 1200-2000 km ₹120, 2000+ km ₹180.',
      },
      {
        'q': 'How do I add a friend?',
        'a':
            'Open any seller profile and tap "Add Friend". They auto-accept in demo mode.',
      },
      {
        'q': 'Where can I see artisans on a map?',
        'a':
            'Open Upload tab → Artisan Map. Your own location is shown too, and you can see distance to any artisan.',
      },
    ];
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('help')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: faqs
              .map((f) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: K.paper,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: K.gold.withValues(alpha: 0.4)),
                    ),
                    child: ExpansionTile(
                      title: Text(f['q']!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: K.maroon,
                              fontSize: 14)),
                      children: <Widget>[
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(f['a']!,
                              style: const TextStyle(
                                  color: K.inkSoft, height: 1.5)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class CouponsScreen extends StatelessWidget {
  const CouponsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('coupons')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: kCoupons.length,
          itemBuilder: (_, i) {
            final c = kCoupons[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    K.gold.withValues(alpha: 0.2),
                    K.gold.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: K.gold, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: K.maroon,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.local_offer,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(c.code,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: K.maroon,
                                  letterSpacing: 2)),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(prov.t('copied')),
                                  backgroundColor: K.leaf),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(c.description,
                        style: const TextStyle(
                            fontSize: 13, color: K.ink, height: 1.4)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('notifications')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
        actions: <Widget>[
          if (prov.unreadNotifCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: prov.markAllNotificationsRead,
            ),
        ],
      ),
      body: Doodle(
        child: prov.notifications.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_none,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    Text(prov.t('no_notifications'),
                        style: const TextStyle(color: K.inkSoft)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: prov.notifications.length,
                itemBuilder: (_, i) {
                  final n = prov.notifications[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: n.read ? K.paper : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: n.read
                            ? K.gold.withValues(alpha: 0.3)
                            : K.maroon,
                        width: n.read ? 1 : 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: K.gold.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.notifications,
                              size: 18, color: K.maroon),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(n.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: K.ink,
                                      fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(n.body,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: K.inkSoft,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  UPLOAD  (with location & map picker)
// ═══════════════════════════════════════════════════════════════════════════
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _t = TextEditingController();
  final _d = TextEditingController();
  final _p = TextEditingController();
  final _hi = TextEditingController();
  final _loc = TextEditingController();
  final _del = TextEditingController();
  final _speech = SpeechService();

  final List<Uint8List> _images = [];
  String _cat = 'Sarees';
  String _voiceLoc = 'te_IN';
  bool _analyzing = false;
  bool _removingBg = false;
  bool _uploading = false;
  bool _showTrans = false;
  bool _listening = false;

  // Product location
  double _productLat = 0;
  double _productLng = 0;
  String _productLocation = '';

  @override
  void initState() {
    super.initState();
    _speech.init();
  }

  @override
  void dispose() {
    _t.dispose();
    _d.dispose();
    _p.dispose();
    _hi.dispose();
    _loc.dispose();
    _del.dispose();
    _speech.stop();
    _speech.stopSpeak();
    super.dispose();
  }

  Future<void> _pickProductLocation() async {
    // ensure user has set their own location first
    final prov = Provider.of<ProductProvider>(context, listen: false);
    if (!prov.hasUserLocation) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const SetLocationPromptScreen()),
      );
      if (ok != true && !prov.hasUserLocation) return;
    }
    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialCenter: prov.hasUserLocation
              ? LatLng(prov.userLat, prov.userLng)
              : null,
          initialAddressLabel:
              prov.hasUserLocation ? prov.userCity : null,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _productLat = result['lat'] as double;
        _productLng = result['lng'] as double;
        _productLocation = result['label'] as String;
        _loc.text = _productLocation;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await ImagePicker()
          .pickMultiImage(imageQuality: 60, maxWidth: 800);
      for (final f in files) {
        final bytes = await f.readAsBytes();
        _images.add(bytes);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final f = await ImagePicker().pickImage(
          source: ImageSource.camera, imageQuality: 60, maxWidth: 800);
      if (f != null) {
        final bytes = await f.readAsBytes();
        if (mounted) setState(() => _images.add(bytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleMic() async {
    if (!_listening) {
      final ok = await _speech.init();
      if (!ok) {
        if (mounted) {
          final prov =
              Provider.of<ProductProvider>(context, listen: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(prov.t('mic_unavailable'))),
          );
        }
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(_voiceLoc, (text) {
        _d.text = text;
      });
    } else {
      await _speech.stop();
      setState(() => _listening = false);
    }
  }

  Future<void> _speakDesc() async {
    if (_d.text.trim().isNotEmpty) {
      await _speech.speak(_d.text, _voiceLoc);
    }
  }

  Map<String, dynamic> _localFallback(String desc, String cat) {
    final d = desc.trim().isEmpty
        ? 'Handcrafted ${cat.toLowerCase()} made with traditional techniques.'
        : desc;
    final base = cat == 'Sarees'
        ? 2500
        : cat == 'Dresses'
            ? 1400
            : cat == 'Jewelry'
                ? 900
                : 800;
    return {
      'title': d.length > 50 ? '${d.substring(0, 47)}…' : d,
      'description_en': '$d Beautifully handcrafted by Indian artisans.',
      'description_hi': 'भारतीय शिल्पकारों द्वारा हस्तनिर्मित।',
      'category': cat,
      'price_low': base,
      'price_high': (base * 1.6).round(),
      'tags': ['handmade', cat.toLowerCase(), 'india'],
      'confidence': 0.5,
    };
  }

  Future<void> _analyzeWithAI() async {
    if (_images.isEmpty) return;
    final prov = Provider.of<ProductProvider>(context, listen: false);
    setState(() => _analyzing = true);
    Map<String, dynamic>? result;
    try {
      result = await AIService.analyzeProduct(
          _images.first, userDesc: _d.text.trim());
    } catch (_) {
      result = null;
    }
    result ??= _localFallback(_d.text.trim(), _cat);
    if (!mounted) return;
    setState(() => _analyzing = false);
    setState(() {
      _t.text = result!['title'] ?? _t.text;
      _d.text = result['description_en'] ?? _d.text;
      _hi.text = result['description_hi'] ?? '';
      final low = result['price_low'] ?? 0;
      final high = result['price_high'] ?? 0;
      if (low > 0 && high > 0) {
        _p.text = '${((low + high) / 2).round()}';
      }
      final detectedCat = result['category'] as String?;
      if (detectedCat != null && kCategories.contains(detectedCat)) {
        _cat = detectedCat;
      }
      _showTrans = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(prov.t('ai_filled')), backgroundColor: K.leaf),
    );
  }

  Future<void> _removeBackground() async {
    if (_images.isEmpty) return;
    final prov = Provider.of<ProductProvider>(context, listen: false);
    setState(() => _removingBg = true);
    final enhanced = <Uint8List>[];
    for (final img in _images) {
      final r = await AIService.removeBackground(img);
      enhanced.add(r ?? img);
    }
    if (!mounted) return;
    setState(() {
      _removingBg = false;
      _images.clear();
      _images.addAll(enhanced);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(prov.t('bg_removed')), backgroundColor: K.leaf),
    );
  }

  Future<void> _submit() async {
    final prov = Provider.of<ProductProvider>(context, listen: false);

    if (_t.text.isEmpty || _p.text.isEmpty || _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prov.t('fill_required'))),
      );
      return;
    }

    // Make sure location is set (product or user fallback)
    if (_productLat == 0 && _productLng == 0 && !prov.hasUserLocation) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const SetLocationPromptScreen()),
      );
      if (ok != true && !prov.hasUserLocation) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please set a location first')),
          );
        }
        return;
      }
    }

    setState(() => _uploading = true);
    final lat = _productLat != 0 ? _productLat : prov.userLat;
    final lng = _productLng != 0 ? _productLng : prov.userLng;
    final loc = _productLocation.isNotEmpty
        ? _productLocation
        : (prov.userCity.isNotEmpty ? prov.userCity : _loc.text.trim());

    await prov.addProduct(
      title: _t.text.trim(),
      description: _d.text.trim(),
      descriptionHi: _hi.text.trim(),
      price: double.tryParse(_p.text) ?? 0,
      images: List<Uint8List>.from(_images),
      category: _cat,
      location: loc,
      deliveryInfo: _del.text.trim(),
      lat: lat,
      lng: lng,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(prov.t('uploaded')), backgroundColor: K.leaf),
    );
    _t.clear();
    _d.clear();
    _p.clear();
    _hi.clear();
    _loc.clear();
    _del.clear();
    setState(() {
      _images.clear();
      _showTrans = false;
      _productLat = 0;
      _productLng = 0;
      _productLocation = '';
    });
  }

  void _imgOpts() {
    final prov = Provider.of<ProductProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: K.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt, color: K.maroon),
              title: Text(prov.t('take_photo')),
              onTap: () {
                Navigator.pop(context);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: K.maroon),
              title: Text(prov.t('from_gallery')),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final hasLoc = _productLat != 0 || prov.hasUserLocation;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FadeSlideIn(
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(width: 4, height: 24, color: K.gold),
                    const SizedBox(width: 10),
                    Text(prov.t('list_new_craft'),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: K.maroon)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('Artisan Map',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const IndiaMapScreen()),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: const Text('Festival Calendar',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CalendarScreen()),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ─── LOCATION CARD ───
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hasLoc
                    ? K.leaf.withValues(alpha: 0.1)
                    : K.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasLoc
                      ? K.leaf.withValues(alpha: 0.5)
                      : K.maroon.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    hasLoc ? Icons.location_on : Icons.location_off,
                    color: hasLoc ? K.leaf : K.maroon,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          hasLoc
                              ? (_productLocation.isNotEmpty
                                  ? _productLocation
                                  : prov.userCity)
                              : 'Set shipping location',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: hasLoc ? K.leaf : K.maroon,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasLoc
                              ? 'Buyers see exact distance & delivery ETA'
                              : 'Required — tap to pin your shop on map',
                          style: const TextStyle(
                              fontSize: 11, color: K.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickProductLocation,
                    icon: const Icon(Icons.map, size: 16),
                    label: Text(
                      hasLoc ? 'Change' : 'Set',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _cat,
            decoration: InputDecoration(
              labelText: prov.t('category'),
              prefixIcon:
                  const Icon(Icons.category_outlined, color: K.maroon),
            ),
            items: kCategories
                .where((c) => c != 'All')
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _cat = v ?? 'Sarees'),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text('${prov.t('photos')} (${_images.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: K.maroon,
                      fontSize: 14)),
              const Spacer(),
              if (_images.isNotEmpty)
                TextButton.icon(
                  onPressed: _imgOpts,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(prov.t('add_more'),
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_images.isEmpty) _buildEmptyPhoto() else _buildPhotoList(prov),
          const SizedBox(height: 12),
          if (_images.isNotEmpty && !_analyzing && !_removingBg)
            ...<Widget>[
              ElevatedButton.icon(
                onPressed: _analyzeWithAI,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AI Auto-Fill Everything',
                    style: TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: K.gold,
                  foregroundColor: K.maroon,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(0, 54),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _removeBackground,
                icon: const Icon(Icons.image_outlined),
                label: Text(prov.t('remove_bg')),
              ),
            ],
          const SizedBox(height: 20),
          _lbl(prov.t('title')),
          TextField(
            controller: _t,
            decoration: InputDecoration(
              hintText: prov.t('title_hint'),
              prefixIcon:
                  const Icon(Icons.edit_outlined, color: K.maroon),
            ),
          ),
          const SizedBox(height: 16),
          _lbl(prov.t('voice_lang')),
          DropdownButtonFormField<String>(
            initialValue: _voiceLoc,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.mic, color: K.maroon),
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'te_IN', child: Text('తెలుగు (Telugu)')),
              DropdownMenuItem(value: 'hi_IN', child: Text('हिन्दी (Hindi)')),
              DropdownMenuItem(value: 'en_US', child: Text('English')),
            ],
            onChanged: (v) => setState(() => _voiceLoc = v ?? 'te_IN'),
          ),
          const SizedBox(height: 16),
          _lbl('${prov.t('description')} (English)'),
          TextField(
            controller: _d,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: prov.t('desc_hint'),
              suffixIcon: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? Colors.red : K.maroon,
                    ),
                    onPressed: _toggleMic,
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up, color: K.maroon),
                    onPressed: _speakDesc,
                  ),
                ],
              ),
            ),
          ),
          if (_showTrans) ...<Widget>[
            const SizedBox(height: 16),
            _lbl('विवरण (हिन्दी)'),
            TextField(controller: _hi, maxLines: 3),
          ],
          const SizedBox(height: 16),
          _lbl(prov.t('location')),
          TextField(
            controller: _loc,
            decoration: InputDecoration(
              hintText: prov.t('location_hint'),
              prefixIcon: const Icon(Icons.location_on_outlined,
                  color: K.maroon),
              suffixIcon: IconButton(
                icon: const Icon(Icons.map, color: K.maroon),
                onPressed: _pickProductLocation,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _lbl(prov.t('delivery')),
          TextField(
            controller: _del,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: prov.t('delivery_hint'),
              prefixIcon: const Icon(Icons.local_shipping_outlined,
                  color: K.maroon),
            ),
          ),
          const SizedBox(height: 16),
          _lbl(prov.t('price')),
          TextField(
            controller: _p,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: prov.t('price_hint'),
              prefixIcon:
                  const Icon(Icons.currency_rupee, color: K.maroon),
            ),
          ),
          const SizedBox(height: 26),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _submit,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(
              _uploading ? prov.t('loading') : prov.t('save_listing'),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPhoto() => GestureDetector(
        onTap: (_analyzing || _removingBg) ? null : _imgOpts,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: K.paper,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: K.gold.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: K.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_a_photo_outlined,
                      size: 42, color: K.maroon),
                ),
                const SizedBox(height: 14),
                const Text('Tap to add photo',
                    style: TextStyle(color: K.inkSoft, fontSize: 14)),
              ],
            ),
          ),
        ),
      );

  Widget _buildPhotoList(ProductProvider prov) {
    final busy = _analyzing || _removingBg;
    return SizedBox(
      height: 200,
      child: Stack(
        children: <Widget>[
          ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => Stack(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(_images[i],
                      width: 200, height: 200, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                if (i == 0)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: K.gold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Cover',
                          style: TextStyle(
                              color: K.maroon,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const CircularProgressIndicator(color: K.gold),
                      const SizedBox(height: 14),
                      Text(
                        _removingBg ? prov.t('remove_bg') : prov.t('analyzing'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            Container(width: 4, height: 16, color: K.gold),
            const SizedBox(width: 8),
            Text(t,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: K.maroon,
                    fontSize: 14)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  CART
// ═══════════════════════════════════════════════════════════════════════════
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final items = prov.cart.entries.toList();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: K.gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    size: 56, color: K.maroon),
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: Text(prov.t('empty_cart'),
                  style: const TextStyle(fontSize: 16, color: K.ink)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final e = items[i];
              final list =
                  prov.products.where((x) => x.id == e.key).toList();
              if (list.isEmpty) return const SizedBox.shrink();
              final p = list.first;
              final q = e.value;
              return FadeSlideIn(
                key: ValueKey('c_${p.id}'),
                delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: K.paper,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: K.gold.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                            width: 72, height: 72, child: productImg(p)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: K.ink)),
                            Text('₹${p.price.toStringAsFixed(0)} each',
                                style: const TextStyle(
                                    fontSize: 12, color: K.inkSoft)),
                            Row(
                              children: <Widget>[
                                _qty(
                                  icon: Icons.remove,
                                  onTap: () =>
                                      prov.removeFromCart(p.id),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Text('$q',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: K.maroon)),
                                ),
                                _qty(
                                  icon: Icons.add,
                                  onTap: () => prov.addToCart(p.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text('₹${(p.price * q).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: K.maroon)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: K.paper,
              border: Border(
                  top:
                      BorderSide(color: K.gold.withValues(alpha: 0.4))),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('Grand Total',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: K.ink)),
                    const Spacer(),
                    Text('₹${prov.cartTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: K.maroon)),
                  ],
                ),
                if (prov.hasUserLocation && prov.cartCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.local_shipping,
                            size: 14, color: K.leaf),
                        const SizedBox(width: 6),
                        Text(
                          '${prov.t('delivery_fee')}: '
                          '${prov.cartDeliveryFee == 0 ? "FREE" : "₹${prov.cartDeliveryFee.toStringAsFixed(0)}"} · '
                          'ETA ${prov.cartDeliveryDays} day${prov.cartDeliveryDays != 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: K.leaf,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: Text(prov.t('checkout'),
                        style: const TextStyle(fontSize: 16)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CheckoutScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _qty({required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: K.maroon.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: K.maroon),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ADDRESS EDITOR  (with map picker)
// ═══════════════════════════════════════════════════════════════════════════
class AddressEditorScreen extends StatefulWidget {
  final Address? existing;
  const AddressEditorScreen({super.key, this.existing});
  @override
  State<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends State<AddressEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _line;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pin;
  bool _default = false;
  double _lat = 0;
  double _lng = 0;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _name = TextEditingController(text: a?.fullName ?? '');
    _phone = TextEditingController(text: a?.phone ?? '');
    _line = TextEditingController(text: a?.line ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _state = TextEditingController(text: a?.state ?? '');
    _pin = TextEditingController(text: a?.pincode ?? '');
    _default = a?.isDefault ?? false;
    _lat = a?.lat ?? 0;
    _lng = a?.lng ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _line.dispose();
    _city.dispose();
    _state.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialCenter: _lat != 0 ? LatLng(_lat, _lng) : null,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result['lat'] as double;
        _lng = result['lng'] as double;
        _city.text = result['label'] as String;
      });
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _line.text.trim().isEmpty ||
        _city.text.trim().isEmpty ||
        _pin.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all required fields')),
      );
      return;
    }
    final prov = Provider.of<ProductProvider>(context, listen: false);
    if (widget.existing != null) {
      prov.removeAddress(widget.existing!.id);
    }
    prov.addAddress(Address(
      id: widget.existing?.id ?? const Uuid().v4(),
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      line: _line.text.trim(),
      city: _city.text.trim(),
      state: _state.text.trim(),
      pincode: _pin.text.trim(),
      isDefault: _default,
      lat: _lat,
      lng: _lng,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(widget.existing == null
            ? prov.t('add_address')
            : prov.t('edit_address')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _lbl(prov.t('full_name')),
              TextField(controller: _name),
              const SizedBox(height: 14),
              _lbl(prov.t('phone')),
              TextField(controller: _phone,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              _lbl(prov.t('address_line')),
              TextField(controller: _line, maxLines: 2),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _lbl(prov.t('city')),
                        TextField(controller: _city),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _lbl(prov.t('state')),
                        TextField(controller: _state),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _lbl(prov.t('pincode')),
              TextField(controller: _pin,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map),
                label: Text(
                  _lat != 0
                      ? '📍 Location pinned (tap to change)'
                      : 'Pin on Map',
                ),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _default,
                onChanged: (v) => setState(() => _default = v ?? false),
                title: Text(prov.t('set_default')),
                activeColor: K.maroon,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: Text(prov.t('save_address')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: K.maroon,
                fontSize: 13)),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ADDRESS BOOK
// ═══════════════════════════════════════════════════════════════════════════
class AddressBookScreen extends StatelessWidget {
  const AddressBookScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final list = prov.addresses;
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('addresses')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_off,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    Text(prov.t('add_address'),
                        style: const TextStyle(color: K.inkSoft)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddressEditorScreen()),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(prov.t('add_address')),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: K.paper,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: a.isDefault
                            ? K.maroon
                            : K.gold.withValues(alpha: 0.4),
                        width: a.isDefault ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.location_on,
                                color: K.maroon, size: 18),
                            const SizedBox(width: 8),
                            Text(a.fullName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: K.ink)),
                            const Spacer(),
                            if (a.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: K.gold,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(prov.t('default_address'),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: K.maroon,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(a.oneLine,
                            style: const TextStyle(
                                fontSize: 13, color: K.inkSoft)),
                        Text('📞 ${a.phone}',
                            style: const TextStyle(
                                fontSize: 13, color: K.inkSoft)),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            if (!a.isDefault)
                              TextButton(
                                onPressed: () =>
                                    prov.setDefaultAddress(a.id),
                                child: Text(prov.t('set_default')),
                              ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AddressEditorScreen(existing: a),
                                ),
                              ),
                              child: Text(prov.t('edit_address')),
                            ),
                            TextButton(
                              onPressed: () => prov.removeAddress(a.id),
                              child: Text(prov.t('delete_btn'),
                                  style: const TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K.maroon,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddressEditorScreen()),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CHECKOUT
// ═══════════════════════════════════════════════════════════════════════════
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'cod';
  Coupon? _coupon;
  final _couponCtrl = TextEditingController();
  bool _placing = false;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      Provider.of<ProductProvider>(context, listen: false).cartTotal;

  double get _discount {
    if (_coupon == null) return 0;
    final raw = _subtotal * _coupon!.percent / 100;
    return raw > _coupon!.maxDiscount ? _coupon!.maxDiscount : raw;
  }

  double get _delivery {
    final prov = Provider.of<ProductProvider>(context, listen: false);
    if (!prov.hasUserLocation) return _subtotal > 500 ? 0 : 40;
    return prov.cartDeliveryFee;
  }

  int get _deliveryDays {
    final prov = Provider.of<ProductProvider>(context, listen: false);
    return prov.cartDeliveryDays > 0 ? prov.cartDeliveryDays : 4;
  }

  double get _grand => _subtotal - _discount + _delivery;

  void _applyCoupon() {
    final code = _couponCtrl.text.trim().toUpperCase();
    final c = kCoupons.where((x) => x.code == code).toList();
    final prov = Provider.of<ProductProvider>(context, listen: false);
    if (c.isEmpty || _subtotal < c.first.minCart) {
      setState(() => _coupon = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prov.t('invalid_coupon'))),
      );
      return;
    }
    setState(() => _coupon = c.first);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(prov.t('coupon_applied')),
          backgroundColor: K.leaf),
    );
  }

  Future<void> _place() async {
    final prov = Provider.of<ProductProvider>(context, listen: false);
    if (prov.defaultAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a delivery address')),
      );
      return;
    }
    setState(() => _placing = true);
    final total = _grand;
    final count = prov.cartCount;
    await prov.placeOrder(
      total,
      count,
      status: 'confirmed',
      couponCode: _coupon?.code,
      deliveryFee: _delivery,
      deliveryDays: _deliveryDays,
      deliveryAddress: prov.defaultAddress?.oneLine ?? '',
    );
    prov.clearCart();
    if (!mounted) return;
    setState(() => _placing = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderSuccessScreen(total: total, itemCount: count),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final addr = prov.defaultAddress;
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('checkout')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _sectionTitle('📍 ${prov.t('addresses')}'),
              if (addr == null) _emptyAddress(prov) else _addressCard(addr, prov),
              const SizedBox(height: 18),
              _sectionTitle('🚚 ${prov.t('delivery_eta')}'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: K.leaf.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: K.leaf.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.schedule, size: 16, color: K.leaf),
                        const SizedBox(width: 8),
                        Text(
                          'Estimated arrival: ${_deliveryDays} day${_deliveryDays != 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: K.leaf,
                              fontSize: 13),
                        ),
                      ],
                    ),
                    if (addr != null && addr.lat != 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Delivery to: ${addr.city}',
                          style: const TextStyle(
                              fontSize: 12, color: K.inkSoft),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _sectionTitle('💳 ${prov.t('payment_method')}'),
              _payTile('cod', prov.t('cod'), Icons.money),
              _payTile('upi', prov.t('upi'),
                  Icons.account_balance_wallet),
              _payTile('card', prov.t('card'), Icons.credit_card),
              _payTile('netbanking', prov.t('netbanking'),
                  Icons.account_balance),
              const SizedBox(height: 18),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CouponsScreen()),
                ),
                child: _sectionTitle(
                    '🎟️ ${prov.t('coupons')}  (tap to view all)'),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _couponCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'WELCOME10',
                        filled: true,
                        fillColor: K.paper,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _applyCoupon,
                    child: Text(prov.t('apply_coupon')),
                  ),
                ],
              ),
              if (_coupon != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: K.leaf.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: K.leaf),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.check_circle, color: K.leaf),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_coupon!.description,
                              style: const TextStyle(
                                  fontSize: 12, color: K.leaf)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _coupon = null),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              _sectionTitle('📦 Order Summary'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: K.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: K.gold.withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: <Widget>[
                    _sumRow(prov.t('subtotal'), _subtotal),
                    if (_discount > 0)
                      _sumRow(prov.t('discount'), -_discount,
                          color: K.leaf),
                    _sumRow(prov.t('delivery_fee'), _delivery,
                        color: _delivery == 0 ? K.leaf : null),
                    const Divider(),
                    _sumRow(prov.t('grand_total'), _grand, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _placing ? null : _place,
                icon: _placing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(prov.t('place_order'),
                    style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 54)),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(t,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: K.maroon)),
        ),
      );

  Widget _emptyAddress(ProductProvider prov) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: K.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: K.gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.location_off, color: K.maroon),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('No address yet',
                  style: TextStyle(color: K.inkSoft)),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AddressEditorScreen()),
              ),
              child: Text(prov.t('add_address')),
            ),
          ],
        ),
      );

  Widget _addressCard(Address a, ProductProvider prov) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: K.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: K.maroon, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.location_on, color: K.maroon),
                const SizedBox(width: 8),
                Text(a.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: K.ink)),
                const Spacer(),
                if (a.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: K.gold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(prov.t('default_address'),
                        style: const TextStyle(
                            fontSize: 10,
                            color: K.maroon,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.oneLine,
                style: const TextStyle(fontSize: 13, color: K.inkSoft)),
            Text('📞 ${a.phone}',
                style: const TextStyle(fontSize: 13, color: K.inkSoft)),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddressBookScreen()),
                  ),
                  child: Text(prov.t('addresses')),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AddressEditorScreen(existing: a)),
                  ),
                  child: Text(prov.t('edit_address')),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _payTile(String code, String label, IconData icon) {
    final sel = _payment == code;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: sel ? K.maroon.withValues(alpha: 0.08) : K.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: sel ? K.maroon : K.gold.withValues(alpha: 0.4),
          width: sel ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: K.maroon),
        title: Text(label,
            style: TextStyle(
                color: K.ink,
                fontWeight:
                    sel ? FontWeight.bold : FontWeight.w500)),
        trailing: Icon(
          sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: K.maroon,
        ),
        onTap: () => setState(() => _payment = code),
      ),
    );
  }

  Widget _sumRow(String l, double v, {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Text(l,
                style: TextStyle(
                    fontSize: bold ? 15 : 13,
                    color: K.inkSoft,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
            const Spacer(),
            Text('₹${v.abs().toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: bold ? 18 : 14,
                    color: color ?? (bold ? K.maroon : K.ink),
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.w600)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ORDER SUCCESS
// ═══════════════════════════════════════════════════════════════════════════
class OrderSuccessScreen extends StatelessWidget {
  final double total;
  final int itemCount;
  const OrderSuccessScreen(
      {super.key, required this.total, required this.itemCount});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final latest = prov.orders.isNotEmpty ? prov.orders.first : null;
    final oid = latest?['id'] ?? 'N/A';
    final days = (latest?['deliveryDays'] as int?) ?? 4;
    return Scaffold(
      backgroundColor: K.cream,
      body: Doodle(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FadeSlideIn(
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: K.leaf.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: K.leaf, width: 3),
                    ),
                    child: const Icon(Icons.check_circle,
                        color: K.leaf, size: 72),
                  ),
                ),
                const SizedBox(height: 28),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 150),
                  child: Text(prov.t('order_confirmed'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: K.maroon)),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 250),
                  child: Text('Order #$oid',
                      style: const TextStyle(
                          fontSize: 15,
                          color: K.inkSoft,
                          letterSpacing: 1.5)),
                ),
                const SizedBox(height: 8),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    '$itemCount item${itemCount != 1 ? 's' : ''} · ₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: K.maroon),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 350),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: K.leaf.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: K.leaf.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.local_shipping,
                            size: 16, color: K.leaf),
                        const SizedBox(width: 6),
                        Text(
                          'Estimated delivery in $days day${days != 1 ? 's' : ''}',
                          style: const TextStyle(
                              color: K.leaf,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 400),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingScreen(orderId: oid),
                        ),
                      ),
                      icon: const Icon(Icons.local_shipping),
                      label: Text(prov.t('track_order')),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 500),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .popUntil((r) => r.isFirst),
                      child: Text(prov.t('tab_shop')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ORDER TRACKING
// ═══════════════════════════════════════════════════════════════════════════
class OrderTrackingScreen extends StatelessWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    const steps = <Map<String, dynamic>>[
      {'key': 'confirmed', 'icon': Icons.check_circle_outline},
      {'key': 'packed', 'icon': Icons.inventory_2_outlined},
      {'key': 'shipped', 'icon': Icons.local_shipping_outlined},
      {'key': 'out_for_delivery', 'icon': Icons.delivery_dining},
      {'key': 'delivered', 'icon': Icons.home_outlined},
    ];
    const current = 2;

    final order = prov.orders.firstWhere(
      (o) => o['id'] == orderId,
      orElse: () => <String, dynamic>{},
    );
    final days = (order['deliveryDays'] as int?) ?? 4;

    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('order_tracking')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: K.paper,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: K.gold.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${prov.t('order_id')}: #$orderId',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: K.maroon)),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.schedule,
                            size: 14, color: K.inkSoft),
                        const SizedBox(width: 6),
                        Text('Expected delivery in $days days',
                            style: const TextStyle(
                                fontSize: 13, color: K.inkSoft)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ...steps.asMap().entries.map((e) {
                final i = e.key;
                final s = e.value;
                final done = i <= current;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: done ? K.leaf : K.paper,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: done ? K.leaf : K.gold,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            s['icon'] as IconData,
                            color: done ? Colors.white : K.inkSoft,
                            size: 20,
                          ),
                        ),
                        if (i != steps.length - 1)
                          Container(
                            width: 2,
                            height: 46,
                            color: done
                                ? K.leaf
                                : K.gold.withValues(alpha: 0.4),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          prov.t(s['key'] as String),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                done ? FontWeight.bold : FontWeight.normal,
                            color: done ? K.maroon : K.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  CHAT WITH SELLER
// ═══════════════════════════════════════════════════════════════════════════
class ChatWithSellerScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  const ChatWithSellerScreen(
      {super.key, required this.sellerId, required this.sellerName});
  @override
  State<ChatWithSellerScreen> createState() => _ChatWithSellerScreenState();
}

class _ChatWithSellerScreenState extends State<ChatWithSellerScreen> {
  final _txt = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];

  @override
  void initState() {
    super.initState();
    _msgs.add({
      'from': 'them',
      'text': 'Namaste! How can I help you today?',
    });
  }

  @override
  void dispose() {
    _txt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _txt.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _msgs.add({'from': 'me', 'text': t});
    });
    _txt.clear();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _msgs.add({
          'from': 'them',
          'text': 'Thanks for reaching out. I will get back to you shortly.',
        });
      });
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: K.cream,
        appBar: AppBar(
          title: Text(widget.sellerName.split(',').first),
          backgroundColor: K.maroon,
          foregroundColor: Colors.white,
        ),
        body: Doodle(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    final mine = m['from'] == 'me';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.72,
                        ),
                        decoration: BoxDecoration(
                          color: mine ? K.maroon : K.paper,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(mine ? 14 : 2),
                            bottomRight: Radius.circular(mine ? 2 : 14),
                          ),
                          border: Border.all(
                            color: mine
                                ? K.maroon
                                : K.gold.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          m['text'] ?? '',
                          style: TextStyle(
                              fontSize: 14,
                              color: mine ? Colors.white : K.ink,
                              height: 1.4),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: K.paper,
                    border: Border(
                      top: BorderSide(
                          color: K.gold.withValues(alpha: 0.4)),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _txt,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: 'Message…',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                  color: K.gold.withValues(alpha: 0.5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                  color: K.gold.withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: K.maroon,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _send,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.send,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  AI CHAT
// ═══════════════════════════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _txt = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _busy = false;
  final _speech = SpeechService();

  @override
  void initState() {
    super.initState();
    _speech.init();
  }

  @override
  void dispose() {
    _txt.dispose();
    _scroll.dispose();
    _speech.stop();
    _speech.stopSpeak();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _txt.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() {
      _msgs.add({'role': 'user', 'content': t});
      _busy = true;
    });
    _txt.clear();
    _jump();
    final history = _msgs
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();
    final reply = await AIService.chat(history);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msgs.add({
        'role': 'assistant',
        'content': reply ?? 'Assistant unavailable. Try again.',
      });
    });
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _mic() async {
    final ok = await _speech.init();
    if (!ok) {
      if (!mounted) return;
      final prov = Provider.of<ProductProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prov.t('mic_unavailable'))),
      );
      return;
    }
    await _speech.listen('en_US', (t) {
      if (mounted) setState(() => _txt.text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('chat_title')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _msgs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: K.gold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.auto_awesome,
                                  size: 48, color: K.maroon),
                            ),
                            const SizedBox(height: 18),
                            Text(prov.t('chat_empty'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: K.inkSoft,
                                    height: 1.5,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final mine = m['role'] == 'user';
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width *
                                  0.78,
                            ),
                            decoration: BoxDecoration(
                              color: mine ? K.maroon : K.paper,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft:
                                    Radius.circular(mine ? 14 : 2),
                                bottomRight:
                                    Radius.circular(mine ? 2 : 14),
                              ),
                              border: Border.all(
                                color: mine
                                    ? K.maroon
                                    : K.gold.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              m['content'] ?? '',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: mine ? Colors.white : K.ink,
                                  height: 1.45),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: K.maroon),
                    ),
                    SizedBox(width: 10),
                    Text('Thinking…',
                        style: TextStyle(
                            color: K.inkSoft, fontSize: 12)),
                  ],
                ),
              ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: K.paper,
                  border: Border(
                    top: BorderSide(
                        color: K.gold.withValues(alpha: 0.4)),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.mic, color: K.maroon),
                      onPressed: _mic,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _txt,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: prov.t('chat_hint'),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: K.gold.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: K.gold.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: K.maroon,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _send,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.send,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PROFILE
// ═══════════════════════════════════════════════════════════════════════════
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final me = prov.me;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        children: <Widget>[
          FadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[K.maroon, K.deepMaroon],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: K.maroon.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: K.gold,
                    backgroundImage: me?.photoUrl != null
                        ? NetworkImage(me!.photoUrl!)
                        : null,
                    child: me?.photoUrl == null
                        ? const Icon(Icons.person,
                            size: 40, color: K.maroon)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    me?.displayName.isNotEmpty == true
                        ? me!.displayName
                        : 'Artisan',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(me?.email ?? '',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12)),
                  if (prov.hasUserLocation)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.location_on,
                              size: 12, color: K.goldLight),
                          const SizedBox(width: 4),
                          Text(prov.userCity,
                              style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.9),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  if (me?.bio.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(me!.bio,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.9),
                              fontSize: 13,
                              height: 1.4)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _menuTile(context, Icons.storefront, prov.t('my_shop'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const MyShopScreen()))),
          _menuTile(context, Icons.favorite_border, prov.t('wishlist'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const WishlistScreen()))),
          _menuTile(context, Icons.receipt_long, prov.t('orders'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const OrdersScreen()))),
          _menuTile(
              context,
              Icons.location_on_outlined,
              prov.t('addresses'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const AddressBookScreen()))),
          _menuTile(context, Icons.people_outline, 'Friends',
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const FriendsScreen()))),
          _menuTile(
              context,
              Icons.notifications_none,
              prov.t('notifications'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const NotificationsScreen()))),
          _menuTile(context, Icons.local_offer_outlined, prov.t('coupons'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const CouponsScreen()))),
          _menuTile(context, Icons.help_outline, prov.t('help'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const HelpScreen()))),
          _menuTile(context, Icons.info_outline, prov.t('about'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const AboutScreen()))),
          _menuTile(context, Icons.settings, prov.t('settings'),
              () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const SettingsScreen()))),
          const SizedBox(height: 10),
          _menuTile(context, Icons.logout, prov.t('logout'), () async {
            final c = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: K.cream,
                title: Text(prov.t('logout')),
                content: const Text('Are you sure?'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(prov.t('cancel')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            );
            if (c == true) await AuthService2.signOut();
          }, danger: true),
        ],
      ),
    );
  }

  Widget _menuTile(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: K.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.gold.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(icon, color: danger ? Colors.red : K.maroon),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                          color: danger ? Colors.red : K.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: danger ? Colors.red : K.inkSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MY SHOP
// ═══════════════════════════════════════════════════════════════════════════
class MyShopScreen extends StatelessWidget {
  const MyShopScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final uid = prov.currentUserId;
    final mine = prov.products.where((p) => p.sellerId == uid).toList();
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('my_shop')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: mine.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    Text(prov.t('no_products'),
                        style: const TextStyle(color: K.inkSoft)),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.58,
                ),
                itemCount: mine.length,
                itemBuilder: (_, i) {
                  final p = mine[i];
                  return Stack(
                    children: <Widget>[
                      ProductCard(product: p, useHero: false),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              final c = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: K.cream,
                                  title: Text(prov.t('delete_confirm')),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(prov.t('cancel')),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: Text(prov.t('delete_btn'),
                                          style: const TextStyle(
                                              color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (c == true) {
                                await prov.deleteProduct(p.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(prov.t('deleted')),
                                      backgroundColor: K.leaf,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.delete_outline,
                                  size: 16, color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  WISHLIST
// ═══════════════════════════════════════════════════════════════════════════
class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final items =
        prov.products.where((p) => prov.wishlist.contains(p.id)).toList();
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('wishlist')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_border,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    Text(prov.t('no_wishlist'),
                        style: const TextStyle(color: K.inkSoft)),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.60,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => ProductCard(product: items[i]),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ORDERS
// ═══════════════════════════════════════════════════════════════════════════
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final list = prov.orders;
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        title: Text(prov.t('orders')),
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
      ),
      body: Doodle(
        child: list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: K.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.receipt_long,
                          size: 48, color: K.maroon),
                    ),
                    const SizedBox(height: 16),
                    Text(prov.t('no_orders'),
                        style: const TextStyle(color: K.inkSoft)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final o = list[i];
                  final status = (o['status'] ?? 'confirmed').toString();
                  final placed = o['placedAt'] is DateTime
                      ? o['placedAt'] as DateTime
                      : DateTime.now();
                  final days = (o['deliveryDays'] as int?) ?? 4;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: K.paper,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: K.gold.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.receipt_long,
                                color: K.maroon, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Order #${o['id']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: K.ink,
                                      fontSize: 14)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: K.leaf,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(prov.t(status),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${o['itemCount']} item${(o['itemCount'] ?? 0) != 1 ? 's' : ''} · ₹${(o['total'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(
                              fontSize: 13, color: K.inkSoft),
                        ),
                        Row(
                          children: <Widget>[
                            Text(
                              '${placed.day}/${placed.month}/${placed.year}',
                              style: const TextStyle(
                                  fontSize: 11, color: K.inkSoft),
                            ),
                            const Spacer(),
                            const Icon(Icons.schedule,
                                size: 11, color: K.leaf),
                            const SizedBox(width: 3),
                            Text('$days days',
                                style: const TextStyle(
                                    fontSize: 11, color: K.leaf)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.local_shipping,
                                size: 16),
                            label: Text(prov.t('track_order')),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingScreen(
                                    orderId: o['id'].toString()),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAIN SHELL
// ═══════════════════════════════════════════════════════════════════════════
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);
    final pages = <Widget>[
      const HomeScreen(),
      const UploadScreen(),
      const CartScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: K.cream,
      appBar: AppBar(
        backgroundColor: K.maroon,
        foregroundColor: Colors.white,
        title: AdminLogoWrapper(
          child: Row(
            children: <Widget>[
              const Icon(Icons.local_florist, color: K.goldLight, size: 22),
              const SizedBox(width: 8),
              const Text('Kalakriti',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
        ),
        actions: <Widget>[
          Stack(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                ),
              ),
              if (prov.unreadNotifCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: K.gold, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
        ],
      ),
      body: Doodle(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: K.maroon,
        unselectedItemColor: K.inkSoft,
        backgroundColor: K.paper,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.storefront),
            label: prov.t('tab_shop'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.add_a_photo_outlined),
            label: prov.t('tab_add'),
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: <Widget>[
                const Icon(Icons.shopping_cart_outlined),
                if (prov.cartCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(
                          minWidth: 14, minHeight: 14),
                      decoration: const BoxDecoration(
                          color: K.gold, shape: BoxShape.circle),
                      child: Text(
                        '${prov.cartCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: K.maroon,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            label: prov.t('tab_cart'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            label: prov.t('tab_profile'),
          ),
        ],
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════
//  APP ROOT + MAIN
// ═══════════════════════════════════════════════════════════════════════════
class KalakritiApp extends StatefulWidget {
  const KalakritiApp({super.key});
  @override
  State<KalakritiApp> createState() => _KalakritiAppState();
}

class _KalakritiAppState extends State<KalakritiApp> {
  bool _splashDone = false;

  ThemeData _theme() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: K.cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: K.maroon,
          primary: K.maroon,
          secondary: K.gold,
          surface: K.paper,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: K.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: K.maroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: K.maroon,
            side: const BorderSide(color: K.maroon),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: K.paper,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: K.gold.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: K.gold.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: K.maroon, width: 1.5),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: K.leaf,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: SplashScreen(
            onDone: () => setState(() => _splashDone = true)),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => ProductProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Kalakriti',
        theme: _theme(),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: K.cream,
            body: Center(
                child:
                    CircularProgressIndicator(color: K.maroon)),
          );
        }
        if (snap.data == null) return const LoginScreen();
        final prov = Provider.of<ProductProvider>(context);
        if (!prov.onboarded) return const OnboardingScreen();
        return const MainShell();
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // 🔔 Initialize notifications
  await NotificationService.init();

  // 🔄 Check for app update in background
  unawaited(NotificationService.checkForUpdate());

  // 🔥 Warm up backend (Render free tier cold start)
  unawaited(
    http
        .get(Uri.parse('https://kalak-shetra-ai.onrender.com/'))
        .timeout(const Duration(seconds: 60))
        .catchError((_) => http.Response('', 200)),
  );

  runApp(const KalakritiApp());
}
// ═══════════════════════════════════════════════════════════════════════════
//  LANGUAGE SWITCHER  (paste-and-use widget for Settings)
// ═══════════════════════════════════════════════════════════════════════════
class LanguageSwitcherCard extends StatelessWidget {
  const LanguageSwitcherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<ProductProvider>(context);

    final langs = <Map<String, String>>[
      {'code': 'en', 'label': 'English', 'native': 'English'},
      {'code': 'hi', 'label': 'Hindi', 'native': 'हिन्दी'},
      {'code': 'te', 'label': 'Telugu', 'native': 'తెలుగు'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.translate, color: K.maroon, size: 18),
              const SizedBox(width: 8),
              Text(
                prov.t('select_lang'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: K.maroon,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: langs.map((l) {
              final code = l['code']!;
              final sel = prov.lang == code;
              return GestureDetector(
                onTap: () {
                  prov.setLang(code);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Language: ${l['native']}'),
                      backgroundColor: K.leaf,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? K.maroon : K.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? K.maroon : K.gold.withValues(alpha: 0.6),
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (sel)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check,
                              size: 16, color: Colors.white),
                        ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l['native']!,
                            style: TextStyle(
                              color: sel ? Colors.white : K.maroon,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            l['label']!,
                            style: TextStyle(
                              color: sel
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : K.inkSoft,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
