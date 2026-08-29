package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	// Configuration defaults
	DefaultAPIKey      = "CHANGE_ME_GENERATE_WITH_OPENSSL_RAND_HEX_32"
	DefaultLogPath     = "" // Will be set to ~/ckpool/logs/ckpool.log if not provided
	DefaultUserLogPath = "" // Will be set to ~/ckpool/logs/users if not provided
	DefaultPort        = "8888"
	DefaultStratumHost = "127.0.0.1:3333"
	MaxLines           = 1000
	RateLimitRequests  = 20
	RateLimitWindow    = 60 * time.Second
	CacheSize          = 100
	CacheTTL           = 60 * time.Second
)

var (
	// Global configuration
	apiKey      string
	logPath     string
	userLogPath string
	port        string

	// Server start time for uptime calculation
	serverStartTime = time.Now()

	// Rate limiting
	rateLimiter = NewRateLimiter()

	// Response cache
	responseCache = NewLRUCache(CacheSize)

	// Metrics
	requestCounter int64
	errorCounter   int64
	metricsMutex   sync.RWMutex
)

// RateLimiter tracks request rates per IP
type RateLimiter struct {
	mu      sync.RWMutex
	clients map[string]*clientInfo
}

type clientInfo struct {
	count     int
	resetTime time.Time
}

func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{
		clients: make(map[string]*clientInfo),
	}
	// Clean up old entries periodically
	go rl.cleanup()
	return rl
}

func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for ip, info := range rl.clients {
			if now.After(info.resetTime) {
				delete(rl.clients, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *RateLimiter) Allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	client, exists := rl.clients[ip]

	if !exists || now.After(client.resetTime) {
		rl.clients[ip] = &clientInfo{
			count:     1,
			resetTime: now.Add(RateLimitWindow),
		}
		return true
	}

	if client.count >= RateLimitRequests {
		return false
	}

	client.count++
	return true
}

// LRUCache for response caching
type LRUCache struct {
	mu       sync.RWMutex
	capacity int
	cache    map[string]*cacheEntry
	order    []string
}

type cacheEntry struct {
	data      interface{}
	timestamp time.Time
}

func NewLRUCache(capacity int) *LRUCache {
	return &LRUCache{
		capacity: capacity,
		cache:    make(map[string]*cacheEntry),
		order:    make([]string, 0, capacity),
	}
}

func (c *LRUCache) Get(key string) (interface{}, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	entry, exists := c.cache[key]
	if !exists {
		return nil, false
	}

	// Check if entry has expired
	if time.Since(entry.timestamp) > CacheTTL {
		return nil, false
	}

	return entry.data, true
}

func (c *LRUCache) Set(key string, data interface{}) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// If at capacity, remove oldest
	if len(c.cache) >= c.capacity && c.cache[key] == nil {
		oldest := c.order[0]
		delete(c.cache, oldest)
		c.order = c.order[1:]
	}

	c.cache[key] = &cacheEntry{
		data:      data,
		timestamp: time.Now(),
	}

	// Update order
	c.order = append(c.order, key)
}

// API Response structures - must match Python exactly
type TailResponse struct {
	Lines     []string `json:"lines"`
	Timestamp int64    `json:"timestamp"`
	Error     string   `json:"error,omitempty"`
}

type GrepResponse struct {
	Lines     []string `json:"lines"`
	Pattern   string   `json:"pattern"`
	Timestamp int64    `json:"timestamp"`
}

type FindBlockResponse struct {
	Found     bool     `json:"found"`
	Lines     []string `json:"lines"`
	Height    string   `json:"height"`
	Timestamp int64    `json:"timestamp"`
	Error     string   `json:"error,omitempty"`
}

type UserFileResponse struct {
	Username string      `json:"username"`
	Content  interface{} `json:"content"`
	Raw      bool        `json:"raw,omitempty"`
	Error    string      `json:"error,omitempty"`
}

type StatsResponse struct {
	Hashrate     *string `json:"hashrate"`
	Workers      int     `json:"workers"`
	Users        int     `json:"users"`
	Transactions int     `json:"transactions"`
	BlockHeight  *int    `json:"block_height"`
	Timestamp    int64   `json:"timestamp"`
	Error        string  `json:"error,omitempty"`
}

type UserLogResponse struct {
	Lines     []string `json:"lines"`
	Exists    bool     `json:"exists"`
	Username  string   `json:"username,omitempty"`
	Timestamp int64    `json:"timestamp"`
}

type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp int64  `json:"timestamp"`
	LogExists bool   `json:"log_exists"`
	LogSize   int64  `json:"log_size"`
	Uptime    int64  `json:"uptime"`
	Version   string `json:"version,omitempty"`
}

type MetricsResponse struct {
	Uptime           int64 `json:"uptime"`
	RequestsTotal    int64 `json:"requests_total"`
	ErrorsTotal      int64 `json:"errors_total"`
	RateLimitEntries int   `json:"rate_limit_entries"`
	CacheEntries     int   `json:"cache_entries"`
	Timestamp        int64 `json:"timestamp"`
}

type CoinbaseOutput struct {
	Value    int64  `json:"value"`     // satoshis
	ValueBCH string `json:"value_bch"` // formatted BCH
	Address  string `json:"address"`
	Type     string `json:"type"` // "miner", "pool_fee" or "op_return"
}

type CoinbaseResponse struct {
	Username        string           `json:"username"`
	CoinbaseHex     string           `json:"coinbase_hex"`
	CoinbaseMessage string           `json:"coinbase_message"`
	Outputs         []CoinbaseOutput `json:"outputs"`
	TotalValue      int64            `json:"total_value"`     // satoshis
	TotalValueBCH   string           `json:"total_value_bch"` // formatted BCH
	BlockHeight     *int             `json:"block_height"`
	NetworkBits     string           `json:"network_bits"`
	Timestamp       int64            `json:"timestamp"`
	Error           string           `json:"error,omitempty"`
}

type StratumSubscribe struct {
	ID     int           `json:"id"`
	Method string        `json:"method"`
	Params []interface{} `json:"params"`
}

type StratumResponse struct {
	ID     int             `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  interface{}     `json:"error"`
}

type StratumNotify struct {
	Params []interface{} `json:"params"`
	Method string        `json:"method"`
}

// lastLines returns at most the final n lines of command output, replacing the
// `| tail -n` that the handlers used to get from a shell. Always returns a
// non-nil slice so the JSON encodes as [] rather than null.
func lastLines(output []byte, n int) []string {
	trimmed := strings.TrimSpace(string(output))
	if trimmed == "" {
		return []string{}
	}
	lines := strings.Split(trimmed, "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}

// Middleware for authentication and rate limiting
func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Check Authorization header
		auth := r.Header.Get("Authorization")
		expectedAuth := "Bearer " + apiKey

		// Constant-time: a plain != returns on the first differing byte, so
		// response latency leaks a prefix oracle over the key. ConstantTimeCompare
		// returns 0 on a length mismatch without comparing, which is fine -- the
		// key's length is not the secret.
		if subtle.ConstantTimeCompare([]byte(auth), []byte(expectedAuth)) != 1 {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			incrementErrorCounter()
			return
		}

		// Check rate limit
		clientIP := getClientIP(r)
		if !rateLimiter.Allow(clientIP) {
			http.Error(w, "Too Many Requests", http.StatusTooManyRequests)
			incrementErrorCounter()
			return
		}

		// Set CORS headers
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "application/json")

		incrementRequestCounter()
		next(w, r)
	}
}

func getClientIP(r *http.Request) string {
	ip := r.RemoteAddr
	if idx := strings.LastIndex(ip, ":"); idx != -1 {
		ip = ip[:idx]
	}
	return ip
}

// Handler functions
func handleTail(w http.ResponseWriter, r *http.Request) {
	linesParam := r.URL.Query().Get("lines")
	numLines := 100
	if linesParam != "" {
		if n, err := strconv.Atoi(linesParam); err == nil && n > 0 {
			numLines = min(n, MaxLines)
		}
	}

	// Check if log file exists
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		json.NewEncoder(w).Encode(TailResponse{
			Lines:     []string{},
			Error:     "Log file not found",
			Timestamp: time.Now().Unix(),
		})
		return
	}

	// Execute tail command
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "tail", "-n", strconv.Itoa(numLines), logPath)
	output, err := cmd.Output()

	var lines []string
	if err == nil && len(output) > 0 {
		lines = strings.Split(strings.TrimSpace(string(output)), "\n")
	} else {
		lines = []string{}
	}

	json.NewEncoder(w).Encode(TailResponse{
		Lines:     lines,
		Timestamp: time.Now().Unix(),
	})
}

func handleGrep(w http.ResponseWriter, r *http.Request) {
	pattern := r.URL.Query().Get("pattern")
	if pattern == "" {
		http.Error(w, "Pattern required", http.StatusBadRequest)
		return
	}

	// Check cache
	cacheKey := "grep:" + pattern
	if cached, found := responseCache.Get(cacheKey); found {
		json.NewEncoder(w).Encode(cached)
		return
	}

	// Check if log file exists
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		response := GrepResponse{
			Lines:     []string{},
			Pattern:   pattern,
			Timestamp: time.Now().Unix(),
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	// QuoteMeta escapes REGEX metacharacters, not SHELL ones -- a single quote
	// is not a regex metacharacter and passed through untouched. The result used
	// to be interpolated into an `sh -c` string wrapped in single quotes, so
	//     ?pattern=foo' ; id ; echo '
	// closed the quoting and ran arbitrary commands as the pool's own user.
	//
	// There is no shell here any more. grep receives the pattern as a single
	// argv element via -e, so there is nothing to quote and nothing to break out
	// of. QuoteMeta stays because this endpoint has always matched literally,
	// and `--` stops a log path that begins with a dash being read as a flag.
	escapedPattern := regexp.QuoteMeta(pattern)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "grep", "-a", "-E", "-e", escapedPattern, "--", logPath)
	output, _ := cmd.Output()

	// Replaces the old `| tail -500`, which only existed because of the shell.
	lines := lastLines(output, 500)

	response := GrepResponse{
		Lines:     lines,
		Pattern:   pattern,
		Timestamp: time.Now().Unix(),
	}

	// Cache the response
	responseCache.Set(cacheKey, response)

	json.NewEncoder(w).Encode(response)
}

func handleFindBlock(w http.ResponseWriter, r *http.Request) {
	height := r.URL.Query().Get("height")
	if height == "" {
		http.Error(w, "Block height required", http.StatusBadRequest)
		return
	}

	// Validate height is numeric
	if _, err := strconv.Atoi(height); err != nil {
		http.Error(w, "Block height required", http.StatusBadRequest)
		return
	}

	// Check cache
	cacheKey := "block:" + height
	if cached, found := responseCache.Get(cacheKey); found {
		json.NewEncoder(w).Encode(cached)
		return
	}

	// Check if log file exists
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		response := FindBlockResponse{
			Found:     false,
			Lines:     []string{},
			Height:    height,
			Error:     "Log file not found",
			Timestamp: time.Now().Unix(),
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	// Search patterns
	patterns := []string{
		fmt.Sprintf("Solved and confirmed block %s", height),
		fmt.Sprintf("BLOCK ACCEPTED.*height %s", height),
		fmt.Sprintf("Found block.*%s", height),
	}

	// height is validated numeric above, so this was not exploitable the way
	// /grep was. It is still the same shape -- a caller-derived value
	// interpolated into a shell string -- and one future edit relaxing that
	// validation would make it exploitable silently. No shell here either.
	var allMatches []string
	for _, pattern := range patterns {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		cmd := exec.CommandContext(ctx, "grep", "-a", "-C", "5", "-e", pattern, "--", logPath)
		output, _ := cmd.Output()
		cancel()

		allMatches = append(allMatches, lastLines(output, 50)...)
	}

	response := FindBlockResponse{
		Found:     len(allMatches) > 0,
		Lines:     allMatches,
		Height:    height,
		Timestamp: time.Now().Unix(),
	}

	// Cache found blocks forever
	if response.Found {
		responseCache.Set(cacheKey, response)
	}

	json.NewEncoder(w).Encode(response)
}

func handleUserFile(w http.ResponseWriter, r *http.Request) {
	username := r.URL.Query().Get("user")
	if username == "" {
		http.Error(w, "Username required", http.StatusBadRequest)
		return
	}

	// Sanitize username
	username = filepath.Base(username)
	// Was hardcoded to /home/elo/ckpool/logs/users, which 404s on any host where
	// the pool does not run as `elo`. handleUserLog already derives this from
	// CKPOOL_USER_LOGS_PATH; this handler was the one that got missed.
	userFile := filepath.Join(userLogPath, username)

	// Check if file exists
	info, err := os.Stat(userFile)
	if os.IsNotExist(err) {
		json.NewEncoder(w).Encode(UserFileResponse{
			Error:    "User not found",
			Username: username,
		})
		return
	}

	// Check file size (1MB limit)
	if info.Size() > 1024*1024 {
		json.NewEncoder(w).Encode(UserFileResponse{
			Error:    "File too large",
			Username: username,
		})
		return
	}

	// Read file
	data, err := os.ReadFile(userFile)
	if err != nil {
		json.NewEncoder(w).Encode(UserFileResponse{
			Error:    err.Error(),
			Username: username,
		})
		return
	}

	// Try to parse as JSON
	var jsonContent interface{}
	if err := json.Unmarshal(data, &jsonContent); err == nil {
		json.NewEncoder(w).Encode(UserFileResponse{
			Username: username,
			Content:  jsonContent,
		})
	} else {
		// Return as raw string if not JSON
		json.NewEncoder(w).Encode(UserFileResponse{
			Username: username,
			Content:  string(data),
			Raw:      true,
		})
	}
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	// Check cache
	cacheKey := "stats"
	if cached, found := responseCache.Get(cacheKey); found {
		if cachedStats, ok := cached.(StatsResponse); ok {
			if time.Now().Unix()-cachedStats.Timestamp < 30 {
				json.NewEncoder(w).Encode(cached)
				return
			}
		}
	}

	// Initialize response with nulls (matching Python)
	response := StatsResponse{
		Hashrate:     nil,
		Workers:      0,
		Users:        0,
		Transactions: 0,
		BlockHeight:  nil,
		Timestamp:    time.Now().Unix(),
	}

	// Check if log file exists
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		response.Error = "Log file not found"
		json.NewEncoder(w).Encode(response)
		return
	}

	// Get last 200 lines
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "tail", "-n", "200", logPath)
	output, err := cmd.Output()

	if err == nil && len(output) > 0 {
		lines := strings.Split(string(output), "\n")

		// Parse lines in reverse order for most recent data
		for i := len(lines) - 1; i >= 0; i-- {
			line := lines[i]

			// Pool hashrate.
			//
			// ckpool writes an SI-suffixed string: "hashrate1m": "50.8P".
			// The old pattern was ([0-9.E+]+), which matched "50.8" and threw
			// the P away -- reporting 50.8 H/s for 50.8 PH/s, off by 10^15.
			// Capture the whole quoted value and let the consumer scale it.
			if response.Hashrate == nil && strings.Contains(line, `Pool:{"hashrate1m"`) {
				re := regexp.MustCompile(`"hashrate1m":\s*"([^"]+)"`)
				if matches := re.FindStringSubmatch(line); len(matches) > 1 {
					hashrate := matches[1]
					response.Hashrate = &hashrate
				}
			}

			// User and worker counts.
			//
			// ckpool capitalises these on the pool summary line:
			//     Pool:{"runtime": 60, ..., "Users": 1, "Workers": 1, ...}
			// The old code matched lowercase `"workers":`, which occurs only on
			// the PER-USER line, so Workers was read from whichever user
			// happened to appear in the tail and Users -- having no lowercase
			// spelling anywhere -- stayed 0 forever even with miners connected.
			if response.Workers == 0 && strings.Contains(line, `Pool:{"runtime"`) {
				if m := regexp.MustCompile(`"Workers":\s*(\d+)`).FindStringSubmatch(line); len(m) > 1 {
					if workers, err := strconv.Atoi(m[1]); err == nil {
						response.Workers = workers
					}
				}
				if m := regexp.MustCompile(`"Users":\s*(\d+)`).FindStringSubmatch(line); len(m) > 1 {
					if users, err := strconv.Atoi(m[1]); err == nil {
						response.Users = users
					}
				}
			}

			// Transaction count
			if response.Transactions == 0 && strings.Contains(line, "Stored local workbase") {
				re := regexp.MustCompile(`with (\d+) transactions?`)
				if matches := re.FindStringSubmatch(line); len(matches) > 1 {
					if txns, err := strconv.Atoi(matches[1]); err == nil {
						response.Transactions = txns
					}
				}
			}

			// Block height
			if response.BlockHeight == nil && strings.Contains(strings.ToLower(line), "height") {
				re := regexp.MustCompile(`height[:=]\s*(\d+)`)
				if matches := re.FindStringSubmatch(line); len(matches) > 1 {
					if height, err := strconv.Atoi(matches[1]); err == nil {
						response.BlockHeight = &height
					}
				}
			}
		}
	}

	// Cache the response
	responseCache.Set(cacheKey, response)

	json.NewEncoder(w).Encode(response)
}

func handleUserLog(w http.ResponseWriter, r *http.Request) {
	username := r.URL.Query().Get("user")
	if username == "" {
		http.Error(w, "Username required", http.StatusBadRequest)
		return
	}

	linesParam := r.URL.Query().Get("lines")
	numLines := 100
	if linesParam != "" {
		if n, err := strconv.Atoi(linesParam); err == nil && n > 0 {
			numLines = min(n, MaxLines)
		}
	}

	// Sanitize username
	username = filepath.Base(username)
	userLog := filepath.Join(userLogPath, username)

	// Check if file exists
	if _, err := os.Stat(userLog); os.IsNotExist(err) {
		json.NewEncoder(w).Encode(UserLogResponse{
			Lines:  []string{},
			Exists: false,
		})
		return
	}

	// Verify path is within allowed directory
	absPath, _ := filepath.Abs(userLog)
	absUserLogPath, _ := filepath.Abs(userLogPath)
	if !strings.HasPrefix(absPath, absUserLogPath) {
		http.Error(w, "Access denied", http.StatusForbidden)
		return
	}

	// Execute tail command
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "tail", "-n", strconv.Itoa(numLines), userLog)
	output, err := cmd.Output()

	var logLines []string
	if err == nil && len(output) > 0 {
		logLines = strings.Split(strings.TrimSpace(string(output)), "\n")
	} else {
		logLines = []string{}
	}

	json.NewEncoder(w).Encode(UserLogResponse{
		Lines:     logLines,
		Exists:    true,
		Username:  username,
		Timestamp: time.Now().Unix(),
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	logExists := false
	var logSize int64 = 0

	if info, err := os.Stat(logPath); err == nil {
		logExists = true
		logSize = info.Size()
	}

	json.NewEncoder(w).Encode(HealthResponse{
		Status:    "ok",
		Timestamp: time.Now().Unix(),
		LogExists: logExists,
		LogSize:   logSize,
		Uptime:    int64(time.Since(serverStartTime).Seconds()),
		Version:   "3.0.0-go",
	})
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	metricsMutex.RLock()
	requests := requestCounter
	errors := errorCounter
	metricsMutex.RUnlock()

	rateLimiter.mu.RLock()
	rateLimitEntries := len(rateLimiter.clients)
	rateLimiter.mu.RUnlock()

	responseCache.mu.RLock()
	cacheEntries := len(responseCache.cache)
	responseCache.mu.RUnlock()

	json.NewEncoder(w).Encode(MetricsResponse{
		Uptime:           int64(time.Since(serverStartTime).Seconds()),
		RequestsTotal:    requests,
		ErrorsTotal:      errors,
		RateLimitEntries: rateLimitEntries,
		CacheEntries:     cacheEntries,
		Timestamp:        time.Now().Unix(),
	})
}

func handleCoinbase(w http.ResponseWriter, r *http.Request) {
	username := r.URL.Query().Get("user")
	if username == "" {
		username = "anonymous"
	}

	// Check cache
	cacheKey := "coinbase:" + username
	if cached, found := responseCache.Get(cacheKey); found {
		if cachedResp, ok := cached.(CoinbaseResponse); ok {
			if time.Now().Unix()-cachedResp.Timestamp < 10 {
				json.NewEncoder(w).Encode(cached)
				return
			}
		}
	}

	response := CoinbaseResponse{
		Username:  username,
		Timestamp: time.Now().Unix(),
	}

	// Connect to stratum
	conn, err := net.DialTimeout("tcp", DefaultStratumHost, 5*time.Second)
	if err != nil {
		response.Error = fmt.Sprintf("Failed to connect to pool: %v", err)
		json.NewEncoder(w).Encode(response)
		return
	}
	defer conn.Close()

	conn.SetDeadline(time.Now().Add(10 * time.Second))

	// Send mining.subscribe. The parameter is the USERAGENT, not the username --
	// naming it after the caller keeps these probes identifiable in the pool log.
	subscribe := StratumSubscribe{
		ID:     1,
		Method: "mining.subscribe",
		Params: []interface{}{username + "/api"},
	}

	encoder := json.NewEncoder(conn)
	if err := encoder.Encode(subscribe); err != nil {
		response.Error = fmt.Sprintf("Failed to send subscribe: %v", err)
		json.NewEncoder(w).Encode(response)
		return
	}

	// Read responses
	scanner := bufio.NewScanner(conn)
	// mining.notify carries a merkle branch plus both coinbase halves -- well
	// under bufio's default 64KB token cap in practice, but an oversized line
	// would end the scan silently and be misreported below as an authorisation
	// failure. Raise the cap so only a genuine transport fault stops the scan.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	var coinbasePart1, coinbasePart2, networkBits string
	var extranonce1 string
	var extranonce2Size int
	authorized := false

	// In btcsolo mode (-B) ckpool builds a workbase PER USER, at authorise time
	// (src/stratifier.c, generate_user()). A client that only subscribes is
	// never issued a mining.notify at all -- measured against this pool
	// 2026-08-28: subscribe-only received zero jobs, subscribe+authorise
	// received the caller's own coinbase. So the username has to be authorised,
	// not merely passed as a useragent, or this endpoint returns nothing.
	//
	// Authorise as "<user>.ckpool-api" so the phantom worker this creates is
	// obviously ours in the miner's stats. ckpool selects the payout address
	// from the first token of the username, splitting on EITHER '.' or '_'
	// (src/stratifier.c:5466, strsep(&base_username, "._")) -- so split on the
	// same set here rather than on '.' alone, or a name like "addr_rig1" would
	// be truncated differently than ckpool truncates it.
	authUser := username
	if i := strings.IndexAny(authUser, "._"); i >= 0 {
		authUser = authUser[:i]
	}
	authUser += ".ckpool-api"

	for i := 0; i < 24 && scanner.Scan(); i++ {
		line := scanner.Text()

		// The subscribe reply carries extranonce1 and extranonce2_size, both of
		// which are needed to rebuild the coinbase (see below).
		var resp struct {
			ID     int             `json:"id"`
			Result json.RawMessage `json:"result"`
		}
		if json.Unmarshal([]byte(line), &resp) == nil && resp.ID == 1 && len(resp.Result) > 0 {
			var parts []interface{}
			if json.Unmarshal(resp.Result, &parts) == nil && len(parts) >= 3 {
				extranonce1, _ = parts[1].(string)
				if f, ok := parts[2].(float64); ok {
					extranonce2Size = int(f)
				}
			}
			if err := encoder.Encode(StratumSubscribe{
				ID:     2,
				Method: "mining.authorize",
				Params: []interface{}{authUser, "x"},
			}); err != nil {
				response.Error = fmt.Sprintf("Failed to send authorize: %v", err)
				json.NewEncoder(w).Encode(response)
				return
			}
			continue
		}
		if json.Unmarshal([]byte(line), &resp) == nil && resp.ID == 2 {
			var ok bool
			if json.Unmarshal(resp.Result, &ok) == nil {
				authorized = ok
			}
			continue
		}

		var notify StratumNotify
		if err := json.Unmarshal([]byte(line), &notify); err == nil {
			if notify.Method == "mining.notify" && len(notify.Params) >= 9 {
				if cb1, ok := notify.Params[2].(string); ok {
					coinbasePart1 = cb1
				}
				if cb2, ok := notify.Params[3].(string); ok {
					coinbasePart2 = cb2
				}
				if bits, ok := notify.Params[6].(string); ok {
					networkBits = bits
				}
				// Only a post-authorise job is this user's job.
				if authorized {
					break
				}
			}
		}
	}

	// Distinguish a transport fault from an authorisation refusal. The 10s
	// deadline set at connect can expire mid-conversation, ending the scan with
	// Scan()==false; without this the handler falls through and blames the
	// username, sending an operator to debug an auth problem that does not exist.
	if err := scanner.Err(); err != nil {
		// The read can die on either side of the authorise reply, and the two
		// are different faults to chase: no auth yet vs. authorised but the
		// post-authorise mining.notify never arrived.
		stage := "before authorisation completed"
		if authorized {
			stage = "after authorisation, while waiting for a job"
		}
		response.Error = fmt.Sprintf("Stratum read failed %s: %v", stage, err)
		json.NewEncoder(w).Encode(response)
		return
	}

	if !authorized {
		response.Error = fmt.Sprintf("Pool did not authorise %s -- a username that is neither a valid BCH address nor a plain name is rejected outright", authUser)
		json.NewEncoder(w).Encode(response)
		return
	}

	if coinbasePart1 == "" || coinbasePart2 == "" {
		response.Error = "Failed to get coinbase from pool"
		json.NewEncoder(w).Encode(response)
		return
	}

	// Rebuild the coinbase exactly as a miner does:
	//     coinb1 + extranonce1 + extranonce2 + coinb2
	//
	// coinb1 already declares the FULL scriptSig length, extranonce included, so
	// concatenating coinb1+coinb2 alone leaves the parser 12 bytes short (4 for
	// extranonce1, 8 for extranonce2) and every output offset after it is wrong.
	// Measured against this pool 2026-08-28, the truncated form parsed as ONE
	// output of -5970863856677875828 sats (-59,708,638,566 BCH) instead of the
	// real two-output 98/2 split. extranonce2 is zero-filled: its value does not
	// affect the outputs, only its length matters for the offsets.
	response.CoinbaseHex = coinbasePart1 + extranonce1 +
		strings.Repeat("00", extranonce2Size) + coinbasePart2
	response.NetworkBits = networkBits

	// Extract coinbase message from part1
	if msg := extractCoinbaseMessage(coinbasePart1); msg != "" {
		response.CoinbaseMessage = msg
	}

	// Extract block height from part1
	if height := extractBlockHeight(coinbasePart1); height != nil {
		response.BlockHeight = height
	}

	// Parse outputs from the FULL coinbase transaction (coinb1+coinb2).
	// coinb2 alone is ~12 bytes and cannot contain the outputs — parsing it
	// was what made /coinbase report a single bogus multi-million-BCH output.
	outputs, totalValue := parseCoinbaseOutputs(response.CoinbaseHex)
	response.Outputs = outputs
	response.TotalValue = totalValue
	response.TotalValueBCH = fmt.Sprintf("%.8f", float64(totalValue)/100000000.0)

	// Cache the response
	responseCache.Set(cacheKey, response)

	json.NewEncoder(w).Encode(response)
}

// readVarint reads a Bitcoin compact-size integer at data[offset].
//
// Encoding: a first byte < 0xfd is the value itself; 0xfd means a 2-byte
// little-endian value follows; 0xfe a 4-byte one; 0xff an 8-byte one.
// Returns the value, the offset just past it, and false when the buffer is
// too short (callers must abort — this parses network-supplied data).
func readVarint(data []byte, offset int) (uint64, int, bool) {
	if offset < 0 || offset >= len(data) {
		return 0, offset, false
	}

	prefix := data[offset]
	offset++

	switch {
	case prefix < 0xfd:
		return uint64(prefix), offset, true
	case prefix == 0xfd:
		if offset+2 > len(data) {
			return 0, offset, false
		}
		v := uint64(data[offset]) | uint64(data[offset+1])<<8
		return v, offset + 2, true
	case prefix == 0xfe:
		if offset+4 > len(data) {
			return 0, offset, false
		}
		v := uint64(data[offset]) | uint64(data[offset+1])<<8 |
			uint64(data[offset+2])<<16 | uint64(data[offset+3])<<24
		return v, offset + 4, true
	default: // 0xff
		if offset+8 > len(data) {
			return 0, offset, false
		}
		v := uint64(data[offset]) | uint64(data[offset+1])<<8 |
			uint64(data[offset+2])<<16 | uint64(data[offset+3])<<24 |
			uint64(data[offset+4])<<32 | uint64(data[offset+5])<<40 |
			uint64(data[offset+6])<<48 | uint64(data[offset+7])<<56
		return v, offset + 8, true
	}
}

// coinbaseScriptSig returns the scriptSig of the coinbase transaction's single
// input, plus the offset in data just past that input (i.e. where the output
// count varint starts).
//
// A raw transaction is laid out as:
//
//	version(4) | varint input_count | inputs | varint output_count | outputs | locktime(4)
//
// and each input as:
//
//	prevout_hash(32) | prevout_index(4) | varint script_len | script | sequence(4)
//
// This tolerates a TRUNCATED buffer on purpose: stratum's coinb1 is only the
// prefix of the transaction, cut in the middle of the scriptSig, so the
// declared script length routinely exceeds what we hold. In that case the
// available tail is returned and ok is false for the trailing offset.
func coinbaseScriptSig(data []byte) (script []byte, next int, ok bool) {
	offset := 4 // version
	if len(data) < offset {
		return nil, 0, false
	}

	inputCount, offset, ok := readVarint(data, offset)
	if !ok || inputCount == 0 {
		return nil, 0, false
	}

	// prevout hash + index
	if offset+36 > len(data) {
		return nil, 0, false
	}
	offset += 36

	scriptLen, offset, ok := readVarint(data, offset)
	if !ok {
		return nil, 0, false
	}

	end := offset + int(scriptLen)
	if scriptLen > uint64(len(data)) || end < offset || end > len(data) {
		// Truncated (normal for coinb1) — hand back what we actually have.
		return data[offset:], 0, false
	}

	// Skip the 4-byte sequence to land on the output count.
	next = end + 4
	if next > len(data) {
		return data[offset:end], 0, false
	}
	return data[offset:end], next, true
}

// skipCoinbaseHeightPush drops the BIP34 block-height push (a 0x01–0x04 push
// opcode followed by that many little-endian bytes) from the front of a
// coinbase scriptSig, returning the remaining signature bytes.
func skipCoinbaseHeightPush(script []byte) []byte {
	if len(script) == 0 {
		return script
	}
	n := int(script[0])
	if n >= 1 && n <= 4 && len(script) >= 1+n {
		return script[1+n:]
	}
	return script
}

// longestPrintableRun returns the longest maximal run of printable ASCII in b.
// Coinbase scriptSigs interleave the pool signature with binary extranonce
// bytes, so the signature is recovered as the longest readable run rather than
// by stopping at the first delimiter — the previous implementation returned
// "EloPool.cloud/" instead of the real "EloPool.cloud/[Solo]".
func longestPrintableRun(b []byte) string {
	best, start := "", -1
	for i := 0; i <= len(b); i++ {
		printable := i < len(b) && b[i] >= 0x20 && b[i] <= 0x7e
		if printable {
			if start < 0 {
				start = i
			}
			continue
		}
		if start >= 0 {
			if run := string(b[start:i]); len(run) > len(best) {
				best = run
			}
			start = -1
		}
	}
	return best
}

// extractCoinbaseMessage recovers the pool signature from the coinbase input
// script. Accepts either the full coinbase transaction or stratum's coinb1.
func extractCoinbaseMessage(hexStr string) string {
	data, err := hex.DecodeString(hexStr)
	if err != nil {
		return ""
	}

	script, _, _ := coinbaseScriptSig(data)
	if len(script) == 0 {
		return ""
	}

	msg := longestPrintableRun(skipCoinbaseHeightPush(script))
	if len(msg) < 3 {
		return ""
	}
	return msg
}

// extractBlockHeight reads the BIP34 height push at the head of the coinbase
// scriptSig. Accepts either the full coinbase transaction or coinb1.
func extractBlockHeight(hexStr string) *int {
	data, err := hex.DecodeString(hexStr)
	if err != nil {
		return nil
	}

	script, _, _ := coinbaseScriptSig(data)
	if len(script) == 0 {
		return nil
	}

	n := int(script[0])
	if n < 1 || n > 4 || len(script) < 1+n {
		return nil
	}

	height := 0
	for i := 0; i < n; i++ {
		height |= int(script[1+i]) << (8 * i)
	}
	if height <= 0 {
		return nil
	}
	return &height
}

// parseCoinbaseOutputs walks a FULL raw coinbase transaction (coinb1+coinb2)
// and returns its outputs plus their summed value.
//
// It previously received only coinb2 — roughly 12 bytes, which cannot contain
// any output — and treated data[0] (the first byte of the version field) as an
// output count, so /coinbase reported one bogus multi-million-BCH output with
// an empty address. Every length here is a varint and every read is
// bounds-checked; malformed or truncated input yields no outputs, never a panic.
func parseCoinbaseOutputs(hexStr string) ([]CoinbaseOutput, int64) {
	outputs := []CoinbaseOutput{}

	data, err := hex.DecodeString(hexStr)
	if err != nil {
		return outputs, 0
	}

	_, offset, ok := coinbaseScriptSig(data)
	if !ok {
		return outputs, 0
	}

	outputCount, offset, ok := readVarint(data, offset)
	if !ok || outputCount == 0 || outputCount > uint64(len(data)) {
		return outputs, 0
	}

	// A short buffer degrades gracefully: whatever outputs were fully read are
	// kept and the walk stops. Captured coinbases are routinely clipped a few
	// bytes into the final OP_RETURN commitment, and dropping the two real
	// payouts because of that would be worse than reporting them.
	var totalValue int64
	for i := uint64(0); i < outputCount; i++ {
		if offset+8 > len(data) {
			break
		}
		value := int64(binary.LittleEndian.Uint64(data[offset:]))
		offset += 8

		scriptLen, next, ok := readVarint(data, offset)
		if !ok {
			break
		}
		offset = next

		end := offset + int(scriptLen)
		if end < offset || end > len(data) {
			// Truncated scriptPubKey — take the bytes we hold, then stop.
			end = len(data)
		}
		script := data[offset:end]
		offset = end

		out := CoinbaseOutput{
			Value:    value,
			ValueBCH: fmt.Sprintf("%.8f", float64(value)/100000000.0),
		}

		switch {
		case len(script) > 0 && script[0] == 0x6a:
			// OP_RETURN — an unspendable commitment, not a payout.
			out.Type = "op_return"
		case len(script) == 25 && script[0] == 0x76 && script[1] == 0xa9 &&
			script[2] == 0x14 && script[23] == 0x88 && script[24] == 0xac:
			// P2PKH: OP_DUP OP_HASH160 <20> OP_EQUALVERIFY OP_CHECKSIG
			out.Address = encodeLegacyAddress(script[3:23])
			out.Type = "pool_fee"
		default:
			out.Type = "pool_fee"
		}

		outputs = append(outputs, out)
		totalValue += value
	}

	// The payout order is not fixed — the fee output can come first — so the
	// miner output is identified by value, not by index: the largest
	// non-OP_RETURN output is the block reward.
	best := -1
	for i := range outputs {
		if outputs[i].Type == "op_return" {
			continue
		}
		if best < 0 || outputs[i].Value > outputs[best].Value {
			best = i
		}
	}
	if best >= 0 {
		outputs[best].Type = "miner"
	}

	return outputs, totalValue
}

const base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

// encodeLegacyAddress renders a 20-byte HASH160 as a mainnet P2PKH
// Base58Check address (version byte 0x00).
//
// This previously returned fmt.Sprintf("1%x...", pubkeyHash[:8]) — a truncated
// hex placeholder that merely LOOKED like an address. Anything consuming
// /coinbase got a value that could never be paid to or reconciled on-chain.
func encodeLegacyAddress(pubkeyHash []byte) string {
	if len(pubkeyHash) != 20 {
		return ""
	}

	payload := append([]byte{0x00}, pubkeyHash...)
	first := sha256.Sum256(payload)
	second := sha256.Sum256(first[:])
	full := append(payload, second[:4]...)

	// base58 encode
	num := new(big.Int).SetBytes(full)
	radix := big.NewInt(58)
	zero := big.NewInt(0)
	mod := new(big.Int)
	var out []byte
	for num.Cmp(zero) > 0 {
		num.DivMod(num, radix, mod)
		out = append([]byte{base58Alphabet[mod.Int64()]}, out...)
	}
	// leading zero bytes become '1'
	for _, b := range full {
		if b != 0x00 {
			break
		}
		out = append([]byte{'1'}, out...)
	}
	return string(out)
}

func isASCII(s string) bool {
	for _, c := range s {
		if c > 127 || (c < 32 && c != '\n' && c != '\t') {
			return false
		}
	}
	return len(s) > 0
}

func incrementRequestCounter() {
	metricsMutex.Lock()
	requestCounter++
	metricsMutex.Unlock()
}

func incrementErrorCounter() {
	metricsMutex.Lock()
	errorCounter++
	metricsMutex.Unlock()
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func main() {
	// Load configuration from environment
	// Fail closed. Falling back to DefaultAPIKey would start the server on a
	// key published in this repository, while the startup banner below still
	// reported "[SET]" -- an unauthenticated API that looks authenticated.
	// This endpoint exposes the pool's whole log tree, so refuse instead.
	apiKey = os.Getenv("CKPOOL_API_KEY")
	if apiKey == "" || apiKey == DefaultAPIKey {
		log.Fatal("CKPOOL_API_KEY is unset or still the placeholder value. " +
			"Generate one with: openssl rand -hex 32")
	}

	logPath = os.Getenv("CKPOOL_LOG_PATH")
	if logPath == "" {
		// Default to ~/ckpool/logs/ckpool.log
		homeDir, err := os.UserHomeDir()
		if err == nil {
			logPath = filepath.Join(homeDir, "ckpool", "logs", "ckpool.log")
		} else {
			logPath = "/var/log/ckpool/ckpool.log" // Fallback
		}
	}

	userLogPath = os.Getenv("CKPOOL_USER_LOGS_PATH")
	if userLogPath == "" {
		// Default to ~/ckpool/logs/users
		homeDir, err := os.UserHomeDir()
		if err == nil {
			userLogPath = filepath.Join(homeDir, "ckpool", "logs", "users")
		} else {
			userLogPath = "/var/log/ckpool/users" // Fallback
		}
	}

	port = os.Getenv("CKPOOL_API_PORT")
	if port == "" {
		port = DefaultPort
	}

	// Log startup information
	log.Printf("Starting CKPool Log API (Go Version) on port %s", port)
	log.Printf("Log path: %s", logPath)
	log.Printf("User logs path: %s", userLogPath)
	// Unconditionally reachable only because startup now aborts on a missing
	// or placeholder key, so this is a fact rather than an assumption.
	log.Printf("API Key: [SET]")
	log.Printf("Version: 3.0.0-go")
	log.Printf("Features: High performance, low memory, concurrent requests")

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/tail", authMiddleware(handleTail))
	mux.HandleFunc("/grep", authMiddleware(handleGrep))
	mux.HandleFunc("/find-block", authMiddleware(handleFindBlock))
	mux.HandleFunc("/user-file", authMiddleware(handleUserFile))
	mux.HandleFunc("/stats", authMiddleware(handleStats))
	mux.HandleFunc("/user-log", authMiddleware(handleUserLog))
	mux.HandleFunc("/coinbase", authMiddleware(handleCoinbase))
	mux.HandleFunc("/health", authMiddleware(handleHealth))
	mux.HandleFunc("/metrics", authMiddleware(handleMetrics))

	// Create server
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("Shutting down gracefully...")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		server.Shutdown(ctx)
	}()

	// Start server
	log.Printf("Server listening on 0.0.0.0:%s", port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server failed to start: %v", err)
	}

	log.Println("Server stopped")
}
