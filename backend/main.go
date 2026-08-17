package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	_ "modernc.org/sqlite"
)

// ─── Models ────────────────────────────────────────────────────────────────

type Song struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	CoverURL string `json:"coverUrl"`
	Duration int    `json:"duration"`
}

type SearchHistoryEntry struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
	CoverURL string `json:"coverUrl"`
	Type     string `json:"type"`
}

type Artist struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	CoverURL string `json:"coverUrl"`
}

type UserPreference struct {
	ArtistName string `json:"artistName"`
	Score      int    `json:"score"`
}

// ─── DB ────────────────────────────────────────────────────────────────────

var db *sql.DB

func initDB() {
	var err error
	db, err = sql.Open("sqlite", "./ses_music.db")
	if err != nil {
		log.Fatal("Failed to open DB:", err)
	}

	schema := `
	CREATE TABLE IF NOT EXISTS liked_songs (
		id TEXT PRIMARY KEY,
		title TEXT NOT NULL,
		artist TEXT NOT NULL,
		cover_url TEXT NOT NULL,
		duration INTEGER NOT NULL DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS search_history (
		id TEXT NOT NULL,
		title TEXT NOT NULL,
		subtitle TEXT NOT NULL,
		cover_url TEXT NOT NULL,
		type TEXT NOT NULL,
		added_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS followed_artists (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		cover_url TEXT NOT NULL
	);

	CREATE TABLE IF NOT EXISTS user_preferences (
		artist_name TEXT PRIMARY KEY,
		score INTEGER DEFAULT 0
	);
	`
	if _, err := db.Exec(schema); err != nil {
		log.Fatal("Failed to create tables:", err)
	}
	log.Println("✅ Database initialized (Spotify Clone Backend)")
}

// ─── CORS Middleware ───────────────────────────────────────────────────────

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

// ─── Liked Songs Handlers ──────────────────────────────────────────────────

func handleLiked(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query("SELECT id, title, artist, cover_url, duration FROM liked_songs")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		songs := []Song{}
		for rows.Next() {
			var s Song
			if err := rows.Scan(&s.ID, &s.Title, &s.Artist, &s.CoverURL, &s.Duration); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			songs = append(songs, s)
		}
		json.NewEncoder(w).Encode(songs)

	case http.MethodPost:
		var s Song
		if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
			http.Error(w, "Invalid body", http.StatusBadRequest)
			return
		}

		_, err := db.Exec(
			"INSERT OR REPLACE INTO liked_songs (id, title, artist, cover_url, duration) VALUES (?, ?, ?, ?, ?)",
			s.ID, s.Title, s.Artist, s.CoverURL, s.Duration,
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "liked"})

	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			http.Error(w, "Missing id parameter", http.StatusBadRequest)
			return
		}

		_, err := db.Exec("DELETE FROM liked_songs WHERE id = ?", id)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"status": "unliked"})

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func handleLikedCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, "Missing id parameter", http.StatusBadRequest)
		return
	}

	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM liked_songs WHERE id = ?", id).Scan(&count)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]bool{"liked": count > 0})
}

// ─── Search History Handlers ───────────────────────────────────────────────

func handleHistory(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query("SELECT id, title, subtitle, cover_url, type FROM search_history ORDER BY added_at DESC")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		entries := []SearchHistoryEntry{}
		for rows.Next() {
			var e SearchHistoryEntry
			if err := rows.Scan(&e.ID, &e.Title, &e.Subtitle, &e.CoverURL, &e.Type); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			entries = append(entries, e)
		}
		json.NewEncoder(w).Encode(entries)

	case http.MethodPost:
		var e SearchHistoryEntry
		if err := json.NewDecoder(r.Body).Decode(&e); err != nil {
			http.Error(w, "Invalid body", http.StatusBadRequest)
			return
		}

		// Удаляем дубликаты перед вставкой, чтобы запись поднялась наверх
		_, _ = db.Exec("DELETE FROM search_history WHERE id = ?", e.ID)

		_, err := db.Exec(
			"INSERT INTO search_history (id, title, subtitle, cover_url, type) VALUES (?, ?, ?, ?, ?)",
			e.ID, e.Title, e.Subtitle, e.CoverURL, e.Type,
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "added"})

	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			http.Error(w, "Missing id parameter", http.StatusBadRequest)
			return
		}

		var err error
		if id == "all" {
			_, err = db.Exec("DELETE FROM search_history")
		} else {
			_, err = db.Exec("DELETE FROM search_history WHERE id = ?", id)
		}

		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// ─── Artist Following Handlers ─────────────────────────────────────────────

func handleFollow(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rows, err := db.Query("SELECT id, name, cover_url FROM followed_artists")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		artists := []Artist{}
		for rows.Next() {
			var a Artist
			if err := rows.Scan(&a.ID, &a.Name, &a.CoverURL); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			artists = append(artists, a)
		}
		json.NewEncoder(w).Encode(artists)

	case http.MethodPost:
		var a Artist
		if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
			http.Error(w, "Invalid body", http.StatusBadRequest)
			return
		}

		_, err := db.Exec(
			"INSERT OR REPLACE INTO followed_artists (id, name, cover_url) VALUES (?, ?, ?)",
			a.ID, a.Name, a.CoverURL,
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"status": "followed"})

	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			http.Error(w, "Missing id parameter", http.StatusBadRequest)
			return
		}

		_, err := db.Exec("DELETE FROM followed_artists WHERE id = ?", id)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"status": "unfollowed"})

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func handleFollowCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, "Missing id parameter", http.StatusBadRequest)
		return
	}

	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM followed_artists WHERE id = ?", id).Scan(&count)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]bool{"following": count > 0})
}

// ─── Recommendation Handlers ────────────────────────────────────────────────

func handleUpdateScore(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var pref UserPreference
	if err := json.NewDecoder(r.Body).Decode(&pref); err != nil {
		http.Error(w, "Invalid body", http.StatusBadRequest)
		return
	}

	query := `
		INSERT INTO user_preferences (artist_name, score) 
		VALUES (?, ?) 
		ON CONFLICT(artist_name) DO UPDATE SET score = score + ?
	`
	_, err := db.Exec(query, pref.ArtistName, pref.Score, pref.Score)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]string{"status": "updated"})
}

func handleGetTopArtists(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	rows, err := db.Query("SELECT artist_name, score FROM user_preferences ORDER BY score DESC LIMIT 10")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	prefs := []UserPreference{}
	for rows.Next() {
		var p UserPreference
		if err := rows.Scan(&p.ArtistName, &p.Score); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		prefs = append(prefs, p)
	}
	json.NewEncoder(w).Encode(prefs)
}

// ─── Main Entry Point ───────────────────────────────────────────────────────

func main() {
	initDB()
	mux := http.NewServeMux()

	// Recommendations
	mux.HandleFunc("/api/recommend/update", corsMiddleware(handleUpdateScore))
	mux.HandleFunc("/api/recommend/top", corsMiddleware(handleGetTopArtists))

	// Liked Songs
	mux.HandleFunc("/api/liked", corsMiddleware(handleLiked))
	mux.HandleFunc("/api/liked/check", corsMiddleware(handleLikedCheck))

	// Search History
	mux.HandleFunc("/api/history", corsMiddleware(handleHistory))

	// Artist Following
	mux.HandleFunc("/api/artists/following", corsMiddleware(handleFollow))
	mux.HandleFunc("/api/artists/check", corsMiddleware(handleFollowCheck))

	// Search (Pirate API)
	mux.HandleFunc("/api/search", corsMiddleware(handleSearch))
	mux.HandleFunc("/api/radio/popular", corsMiddleware(handleRadioPopular))
	mux.HandleFunc("/ping", corsMiddleware(handlePing))

	port := ":8080"
	fmt.Printf("🎵 Ses Music Server on http://localhost%s\n", port)
	log.Fatal(http.ListenAndServe(port, mux))
}

func handlePing(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("pong"))
}

func handleSearch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	query := r.URL.Query().Get("q")
	if query == "" {
		http.Error(w, "Missing q parameter", http.StatusBadRequest)
		return
	}

	results := SearchAll(query)
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(results)
}

func handleRadioPopular(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	results := GetPopularSongs()
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(results)
}

