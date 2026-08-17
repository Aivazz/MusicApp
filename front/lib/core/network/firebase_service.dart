import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ses/features/library/models/song.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Authentication ──

  /// Выполняет анонимный вход (при первом запуске приложения)
  static Future<User?> signInAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();
      return credential.user;
    } catch (e) {
      print("Firebase Anonymous Auth Error: $e");
      return null;
    }
  }

  /// Выполняет вход через Google и при необходимости объединяет аккаунты
  static Future<User?> signInWithGoogle() async {
    try {
      await GoogleSignIn.instance.initialize();
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) return null; // Отменено пользователем

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final User? prevUser = _auth.currentUser;

      if (prevUser != null && prevUser.isAnonymous) {
        // Если пользователь был анонимным, связываем его данные с аккаунтом Google
        try {
          final linkResult = await prevUser.linkWithCredential(credential);
          return linkResult.user;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use') {
            // Если аккаунт Google уже существует, входим в него
            final loginResult = await _auth.signInWithCredential(credential);
            
            // Переносим данные из анонимного аккаунта в существующий
            await _mergeData(prevUser.uid, loginResult.user!.uid);
            return loginResult.user;
          }
          rethrow;
        }
      } else {
        // Обычный вход
        final loginResult = await _auth.signInWithCredential(credential);
        return loginResult.user;
      }
    } catch (e) {
      print("Firebase Google Auth Error: $e");
      return null;
    }
  }

  /// Выход из аккаунта
  static Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.initialize();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      print("Google Sign Out Error: $e");
    }
  }

  // ── Sync Helper (Слияние данных при логине) ──
  static Future<void> _mergeData(String anonymousUid, String googleUid) async {
    try {
      // 1. Слияние Избранного
      final anonLikedDoc = await _db.collection('users').doc(anonymousUid).collection('data').doc('liked_songs').get();
      if (anonLikedDoc.exists) {
        final googleLikedDoc = await _db.collection('users').doc(googleUid).collection('data').doc('liked_songs').get();
        List<dynamic> googleSongs = googleLikedDoc.exists ? (googleLikedDoc.data()?['songs'] as List? ?? []) : [];
        List<dynamic> anonSongs = anonLikedDoc.data()?['songs'] as List? ?? [];

        // Объединяем без дубликатов по id
        final Map<String, dynamic> mergedSongsMap = {};
        for (var s in googleSongs) {
          mergedSongsMap[s['id']] = s;
        }
        for (var s in anonSongs) {
          mergedSongsMap[s['id']] = s;
        }

        await _db.collection('users').doc(googleUid).collection('data').doc('liked_songs').set({
          'songs': mergedSongsMap.values.toList(),
        });
      }

      // 2. Слияние плейлистов
      final anonPlaylists = await _db.collection('users').doc(anonymousUid).collection('playlists').get();
      for (var doc in anonPlaylists.docs) {
        // Записываем плейлист новому пользователю
        await _db.collection('users').doc(googleUid).collection('playlists').doc(doc.id).set(doc.data());
        // Удаляем из старого
        await doc.reference.delete();
      }

      // 3. Слияние истории
      final anonHistoryDoc = await _db.collection('users').doc(anonymousUid).collection('data').doc('search_history').get();
      if (anonHistoryDoc.exists) {
        await _db.collection('users').doc(googleUid).collection('data').doc('search_history').set(anonHistoryDoc.data()!);
      }

      // 4. Слияние подписок
      final anonFollowDoc = await _db.collection('users').doc(anonymousUid).collection('data').doc('followed_artists').get();
      if (anonFollowDoc.exists) {
        await _db.collection('users').doc(googleUid).collection('data').doc('followed_artists').set(anonFollowDoc.data()!);
      }
    } catch (e) {
      print("Error merging anonymous data with Google account: $e");
    }
  }

  // ── Liked Songs ──

  static Future<void> saveLikedSongs(List<Song> songs) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('liked_songs').set({
        'songs': songs.map((s) => s.toJson()).toList(),
      });
    } catch (e) {
      print("Firestore saveLikedSongs error: $e");
    }
  }

  static Future<List<Song>> getLikedSongs() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('liked_songs').get();
      if (doc.exists) {
        final list = doc.data()?['songs'] as List? ?? [];
        return list.map((j) => Song.fromJson(j)).toList();
      }
    } catch (e) {
      print("Firestore getLikedSongs error: $e");
    }
    return [];
  }

  // ── Playlists ──

  static Future<void> savePlaylist(String id, String name, String coverUrl, List<dynamic> songsJson) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('playlists').doc(id).set({
        'id': id,
        'name': name,
        'coverUrl': coverUrl,
        'songs': songsJson,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Firestore savePlaylist error: $e");
    }
  }

  static Future<void> deletePlaylist(String id) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('playlists').doc(id).delete();
    } catch (e) {
      print("Firestore deletePlaylist error: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> getPlaylists() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final snapshot = await _db.collection('users').doc(uid).collection('playlists').orderBy('updatedAt', descending: true).get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print("Firestore getPlaylists error: $e");
    }
    return [];
  }

  // ── Search History ──

  static Future<void> saveSearchHistory(List<SearchHistoryEntry> history) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('search_history').set({
        'history': history.map((e) => e.toJson()).toList(),
      });
    } catch (e) {
      print("Firestore saveSearchHistory error: $e");
    }
  }

  static Future<List<SearchHistoryEntry>> getSearchHistory() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('search_history').get();
      if (doc.exists) {
        final list = doc.data()?['history'] as List? ?? [];
        return list.map((j) => SearchHistoryEntry.fromJson(j)).toList();
      }
    } catch (e) {
      print("Firestore getSearchHistory error: $e");
    }
    return [];
  }

  // ── Followed Artists ──

  static Future<void> saveFollowedArtists(List<Song> artists) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('followed_artists').set({
        'artists': artists.map((a) => a.toJson()).toList(),
      });
    } catch (e) {
      print("Firestore saveFollowedArtists error: $e");
    }
  }

  static Future<List<Song>> getFollowedArtists() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('followed_artists').get();
      if (doc.exists) {
        final list = doc.data()?['artists'] as List? ?? [];
        return list.map((j) => Song.fromJson(j)).toList();
      }
    } catch (e) {
      print("Firestore getFollowedArtists error: $e");
    }
    return [];
  }

  // ── Artist Recommendation Scores ──

  static Future<void> saveArtistScores(Map<String, int> scores) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('artist_scores').set({
        'scores': scores,
      });
    } catch (e) {
      print("Firestore saveArtistScores error: $e");
    }
  }

  static Future<Map<String, int>> getArtistScores() async {
    final uid = currentUser?.uid;
    if (uid == null) return {};
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('artist_scores').get();
      if (doc.exists) {
        final data = doc.data()?['scores'] as Map<String, dynamic>? ?? {};
        return data.map((key, value) => MapEntry(key, value as int));
      }
    } catch (e) {
      print("Firestore getArtistScores error: $e");
    }
    return {};
  }

  // ── Play History ──

  static Future<void> savePlayHistory(List<PlayHistoryEntry> history) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('play_history').set({
        'history': history.map((e) => e.toJson()).toList(),
      });
    } catch (e) {
      print("Firestore savePlayHistory error: $e");
    }
  }

  static Future<List<PlayHistoryEntry>> getPlayHistory() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('play_history').get();
      if (doc.exists) {
        final list = doc.data()?['history'] as List? ?? [];
        return list.map((j) => PlayHistoryEntry.fromJson(j)).toList();
      }
    } catch (e) {
      print("Firestore getPlayHistory error: $e");
    }
    return [];
  }

  // ── Recent Playlists ──

  static Future<void> saveRecentPlaylists(List<RecentPlaylistEntry> recent) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).collection('data').doc('recent_playlists').set({
        'playlists': recent.map((e) => e.toJson()).toList(),
      });
    } catch (e) {
      print("Firestore saveRecentPlaylists error: $e");
    }
  }

  static Future<List<RecentPlaylistEntry>> getRecentPlaylists() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).collection('data').doc('recent_playlists').get();
      if (doc.exists) {
        final list = doc.data()?['playlists'] as List? ?? [];
        return list.map((j) => RecentPlaylistEntry.fromJson(j)).toList();
      }
    } catch (e) {
      print("Firestore getRecentPlaylists error: $e");
    }
    return [];
  }
}
