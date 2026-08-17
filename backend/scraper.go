package main

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"strconv"
	"sync"
	"time"

	"github.com/PuerkitoBio/goquery"
)

// Default cover URL for scraped songs
const defaultMusicCover = "https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?q=80&w=400&auto=format&fit=crop"

// decryptSefonUrl implements Sefon.pro's custom decryption algorithm
func decryptSefonUrl(dataUrl string, key string) (string, error) {
	if strings.HasPrefix(dataUrl, "#") {
		dataUrl = dataUrl[1:]
	}

	// Reverse key string
	runes := []rune(key)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	reversedKey := string(runes)

	// Custom character-based splitting and reversing
	for _, r := range reversedKey {
		char := string(r)
		parts := strings.Split(dataUrl, char)
		for i, j := 0, len(parts)-1; i < j; i, j = i+1, j-1 {
			parts[i], parts[j] = parts[j], parts[i]
		}
		dataUrl = strings.Join(parts, char)
	}

	// Base64 decode
	decoded, err := base64.StdEncoding.DecodeString(dataUrl)
	if err != nil {
		return "", err
	}
	return string(decoded), nil
}

// parseDurationSeconds converts "MM:SS" or "HH:MM:SS" into total seconds
func parseDurationSeconds(durStr string) int {
	durStr = strings.TrimSpace(durStr)
	if durStr == "" {
		return 210 // default 3:30
	}
	parts := strings.Split(durStr, ":")
	if len(parts) == 2 {
		min, _ := strconv.Atoi(parts[0])
		sec, _ := strconv.Atoi(parts[1])
		return min*60 + sec
	} else if len(parts) == 3 {
		hr, _ := strconv.Atoi(parts[0])
		min, _ := strconv.Atoi(parts[1])
		sec, _ := strconv.Atoi(parts[2])
		return hr*3600 + min*60 + sec
	}
	return 210
}

// SearchSefon scrapes songs from sefon.pro
func SearchSefon(query string) ([]Song, error) {
	searchURL := fmt.Sprintf("https://sefon.pro/search/?q=%s", url.QueryEscape(query))
	req, err := http.NewRequest("GET", searchURL, nil)
	if err != nil {
		return nil, err
	}

	// Sefon checks User-Agent to prevent basic crawlers
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://sefon.pro/")

	client := &http.Client{
		Timeout: 8 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("sefon returned status %d", resp.StatusCode)
	}

	doc, err := goquery.NewDocumentFromReader(resp.Body)
	if err != nil {
		return nil, err
	}

	// First, let's map any artist photos on this page to use as cover fallbacks
	artistPhotos := make(map[string]string)
	doc.Find(".b_list_artists .li").Each(func(i int, s *goquery.Selection) {
		artistName := strings.ToLower(strings.TrimSpace(s.Find(".name").Text()))
		photoSrc, exists := s.Find("img").Attr("src")
		if exists && artistName != "" {
			if !strings.HasPrefix(photoSrc, "http") {
				photoSrc = "https://sefon.pro" + photoSrc
			}
			artistPhotos[artistName] = photoSrc
		}
	})

	var songs []Song
	doc.Find(".b_list_mp3s .mp3").Each(func(i int, s *goquery.Selection) {
		idAttr, _ := s.Attr("data-mp3_id")
		if idAttr == "" {
			return
		}

		artist := strings.TrimSpace(s.Find(".title .artist_name").Text())
		title := strings.TrimSpace(s.Find(".title .song_name").Text())
		durationStr := strings.TrimSpace(s.Find(".duration .value").Text())

		protectedSpan := s.Find(".url_protected")
		encUrl, _ := protectedSpan.Attr("data-url")
		key, _ := protectedSpan.Attr("data-key")

		if encUrl == "" || key == "" {
			return
		}

		streamUrl, err := decryptSefonUrl(encUrl, key)
		if err != nil {
			fmt.Printf("Sefon decryption error for track %s: %v\n", idAttr, err)
			return
		}

		// Choose cover
		cover := defaultMusicCover
		if artistPhoto, exists := artistPhotos[strings.ToLower(artist)]; exists {
			cover = artistPhoto
		}

		songs = append(songs, Song{
			ID:       "sefon_" + idAttr,
			Title:    title,
			Artist:   artist,
			CoverURL: cover,
			Duration: parseDurationSeconds(durationStr),
		})

		// Modify stream URL reference in DB / Response.
		// We will store the actual stream URL inside the videoId field of the model
		// so that the Flutter app can play it directly without further resolution.
		songs[len(songs)-1].ID = streamUrl // Set stream URL as ID/videoId to skip resolve step if we want, or keep ID clean.
	})

	return songs, nil
}

// SearchDriveMusic scrapes songs from drivemusic.club
func SearchDriveMusic(query string) ([]Song, error) {
	searchURL := fmt.Sprintf("https://drivemusic.club/?do=search&subaction=search&story=%s", url.QueryEscape(query))
	req, err := http.NewRequest("GET", searchURL, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://drivemusic.club/")

	client := &http.Client{
		Timeout: 8 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("drivemusic returned status %d", resp.StatusCode)
	}

	doc, err := goquery.NewDocumentFromReader(resp.Body)
	if err != nil {
		return nil, err
	}

	var songs []Song
	doc.Find(".genre-music .music-popular-wrapper").Each(func(i int, s *goquery.Selection) {
		btn := s.Find(".btn_player button")
		streamUrl, exists := btn.Attr("data-url")
		if !exists || streamUrl == "" {
			return
		}

		title := strings.TrimSpace(s.Find(".popular-play-name .popular-play-author").Text())
		artist := strings.TrimSpace(s.Find(".popular-play-name .popular-play-composition").Text())
		durationStr := strings.TrimSpace(s.Find(".popular-download .popular-download-number").Text())

		// Clean up artist name (often contains "feat." or multiple spaces)
		artist = strings.ReplaceAll(artist, "\n", " ")
		artist = strings.Join(strings.Fields(artist), " ")

		songs = append(songs, Song{
			ID:       streamUrl, // Set stream URL as the primary identifier
			Title:    title,
			Artist:   artist,
			CoverURL: defaultMusicCover,
			Duration: parseDurationSeconds(durationStr),
		})
	})

	return songs, nil
}

// SearchAll runs both scrapers concurrently and merges the results
func SearchAll(query string) []Song {
	var wg sync.WaitGroup
	var sefonSongs, dmSongs []Song
	var sefonErr, dmErr error

	wg.Add(2)
	go func() {
		defer wg.Done()
		sefonSongs, sefonErr = SearchSefon(query)
		if sefonErr != nil {
			fmt.Printf("Sefon search error: %v\n", sefonErr)
		}
	}()

	go func() {
		defer wg.Done()
		dmSongs, dmErr = SearchDriveMusic(query)
		if dmErr != nil {
			fmt.Printf("DriveMusic search error: %v\n", dmErr)
		}
	}()

	wg.Wait()

	// Merge results alternately to give a nice mix
	var merged []Song
	i, j := 0, 0
	for i < len(sefonSongs) || j < len(dmSongs) {
		if i < len(sefonSongs) {
			merged = append(merged, sefonSongs[i])
			i++
		}
		if j < len(dmSongs) {
			merged = append(merged, dmSongs[j])
			j++
		}
	}

	return merged
}

// ScrapePopularSefon scrapes popular/trending songs from the homepage of sefon.pro
func ScrapePopularSefon() ([]Song, error) {
	req, err := http.NewRequest("GET", "https://sefon.pro/", nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://sefon.pro/")

	client := &http.Client{
		Timeout: 8 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("sefon returned status %d", resp.StatusCode)
	}

	doc, err := goquery.NewDocumentFromReader(resp.Body)
	if err != nil {
		return nil, err
	}

	artistPhotos := make(map[string]string)
	doc.Find(".b_list_artists .li").Each(func(i int, s *goquery.Selection) {
		artistName := strings.ToLower(strings.TrimSpace(s.Find(".name").Text()))
		photoSrc, exists := s.Find("img").Attr("src")
		if exists && artistName != "" {
			if !strings.HasPrefix(photoSrc, "http") {
				photoSrc = "https://sefon.pro" + photoSrc
			}
			artistPhotos[artistName] = photoSrc
		}
	})

	var songs []Song
	doc.Find(".b_list_mp3s .mp3").Each(func(i int, s *goquery.Selection) {
		idAttr, _ := s.Attr("data-mp3_id")
		if idAttr == "" {
			return
		}

		artist := strings.TrimSpace(s.Find(".title .artist_name").Text())
		title := strings.TrimSpace(s.Find(".title .song_name").Text())
		durationStr := strings.TrimSpace(s.Find(".duration .value").Text())

		protectedSpan := s.Find(".url_protected")
		encUrl, _ := protectedSpan.Attr("data-url")
		key, _ := protectedSpan.Attr("data-key")

		if encUrl == "" || key == "" {
			return
		}

		streamUrl, err := decryptSefonUrl(encUrl, key)
		if err != nil {
			return
		}

		cover := defaultMusicCover
		if artistPhoto, exists := artistPhotos[strings.ToLower(artist)]; exists {
			cover = artistPhoto
		}

		songs = append(songs, Song{
			ID:       streamUrl,
			Title:    title,
			Artist:   artist,
			CoverURL: cover,
			Duration: parseDurationSeconds(durationStr),
		})
	})

	return songs, nil
}

// ScrapePopularDriveMusic scrapes popular/trending songs from the homepage of drivemusic.club
func ScrapePopularDriveMusic() ([]Song, error) {
	req, err := http.NewRequest("GET", "https://drivemusic.club/", nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://drivemusic.club/")

	client := &http.Client{
		Timeout: 8 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("drivemusic returned status %d", resp.StatusCode)
	}

	doc, err := goquery.NewDocumentFromReader(resp.Body)
	if err != nil {
		return nil, err
	}

	var songs []Song
	doc.Find(".genre-music .music-popular-wrapper").Each(func(i int, s *goquery.Selection) {
		btn := s.Find(".btn_player button")
		streamUrl, exists := btn.Attr("data-url")
		if !exists || streamUrl == "" {
			return
		}

		title := strings.TrimSpace(s.Find(".popular-play-name .popular-play-author").Text())
		artist := strings.TrimSpace(s.Find(".popular-play-name .popular-play-composition").Text())
		durationStr := strings.TrimSpace(s.Find(".popular-download .popular-download-number").Text())

		artist = strings.ReplaceAll(artist, "\n", " ")
		artist = strings.Join(strings.Fields(artist), " ")

		songs = append(songs, Song{
			ID:       streamUrl,
			Title:    title,
			Artist:   artist,
			CoverURL: defaultMusicCover,
			Duration: parseDurationSeconds(durationStr),
		})
	})

	return songs, nil
}

// GetPopularSongs fetches trending tracks from Sefon and DriveMusic, returning a nice mixed queue
func GetPopularSongs() []Song {
	var wg sync.WaitGroup
	var sefonSongs, dmSongs []Song

	wg.Add(2)
	go func() {
		defer wg.Done()
		var err error
		sefonSongs, err = ScrapePopularSefon()
		if err != nil {
			fmt.Printf("Sefon popular scrape error: %v\n", err)
		}
	}()

	go func() {
		defer wg.Done()
		var err error
		dmSongs, err = ScrapePopularDriveMusic()
		if err != nil {
			fmt.Printf("DriveMusic popular scrape error: %v\n", err)
		}
	}()

	wg.Wait()

	// Merge alternately
	var merged []Song
	i, j := 0, 0
	for i < len(sefonSongs) || j < len(dmSongs) {
		if i < len(sefonSongs) {
			merged = append(merged, sefonSongs[i])
			i++
		}
		if j < len(dmSongs) {
			merged = append(merged, dmSongs[j])
			j++
		}
	}

	// Fallback list of top CIS and foreign tracks in case scraper fails or internet goes down
	if len(merged) == 0 {
		fmt.Println("⚠️ Both popular scrapers failed. Returning fallback top tracks.")
		fallbackSongs := []Song{
			{ID: "pirate:search:Miyagi & Andy Panda - Minor", Title: "Minor", Artist: "Miyagi & Andy Panda", CoverURL: defaultMusicCover, Duration: 210},
			{ID: "pirate:search:Macan - Asphalt 8", Title: "Asphalt 8", Artist: "Macan", CoverURL: defaultMusicCover, Duration: 180},
			{ID: "pirate:search:Anna Asti - Царица", Title: "Царица", Artist: "Anna Asti", CoverURL: defaultMusicCover, Duration: 220},
			{ID: "pirate:search:Jony - Комета", Title: "Комета", Artist: "Jony", CoverURL: defaultMusicCover, Duration: 195},
			{ID: "pirate:search:Скриптонит - Положение", Title: "Положение", Artist: "Скриптонит", CoverURL: defaultMusicCover, Duration: 240},
			{ID: "pirate:search:HammAli & Navai - Птичка", Title: "Птичка", Artist: "HammAli & Navai", CoverURL: defaultMusicCover, Duration: 190},
			{ID: "pirate:search:Zivert - Life", Title: "Life", Artist: "Zivert", CoverURL: defaultMusicCover, Duration: 205},
			{ID: "pirate:search:Кайрат Нуртас - Махаббат бер маған", Title: "Махаббат бер маған", Artist: "Кайрат Нуртас", CoverURL: defaultMusicCover, Duration: 215},
			{ID: "pirate:search:Jahangir - Не улетай", Title: "Не улетай", Artist: "Jahangir", CoverURL: defaultMusicCover, Duration: 190},
			{ID: "pirate:search:The Weeknd - Blinding Lights", Title: "Blinding Lights", Artist: "The Weeknd", CoverURL: defaultMusicCover, Duration: 200},
			{ID: "pirate:search:Billie Eilish - Bad Guy", Title: "Bad Guy", Artist: "Billie Eilish", CoverURL: defaultMusicCover, Duration: 194},
			{ID: "pirate:search:Eminem - Without Me", Title: "Without Me", Artist: "Eminem", CoverURL: defaultMusicCover, Duration: 290},
			{ID: "pirate:search:Drake - Hotline Bling", Title: "Hotline Bling", Artist: "Drake", CoverURL: defaultMusicCover, Duration: 267},
			{ID: "pirate:search:Dua Lipa - Levitating", Title: "Levitating", Artist: "Dua Lipa", CoverURL: defaultMusicCover, Duration: 203},
			{ID: "pirate:search:Travis Scott - Goosebumps", Title: "Goosebumps", Artist: "Travis Scott", CoverURL: defaultMusicCover, Duration: 242},
			{ID: "pirate:search:Ed Sheeran - Shape of You", Title: "Shape of You", Artist: "Ed Sheeran", CoverURL: defaultMusicCover, Duration: 233},
			{ID: "pirate:search:Bruno Mars - Uptown Funk", Title: "Uptown Funk", Artist: "Bruno Mars", CoverURL: defaultMusicCover, Duration: 270},
			{ID: "pirate:search:Justin Bieber - Stay", Title: "Stay", Artist: "Justin Bieber", CoverURL: defaultMusicCover, Duration: 141},
		}
		return fallbackSongs
	}

	return merged
}
