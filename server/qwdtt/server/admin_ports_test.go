package main

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
)

func TestAdminRejectsMalformedPortsWithoutCreatingSubscription(t *testing.T) {
	previousDB, previousFile, previousKeys := db, dbFile, serverWrapKeys
	db = &Database{Passwords: map[string]*PasswordEntry{}, Devices: map[string]*ClientDevice{}}
	dbFile = filepath.Join(t.TempDir(), "passwords.json")
	serverWrapKeys = newWrapKeyStore()
	setAdminAPIToken("synthetic-token")
	t.Cleanup(func() { db, dbFile, serverWrapKeys = previousDB, previousFile, previousKeys; setAdminAPIToken("") })
	mux := http.NewServeMux()
	registerAdminAPIRoutes(mux)
	for _, ports := range []string{"1,2", "1,2,0", "1,2,65536", "1,2,no", "1,2,3,4"} {
		fields := url.Values{"vk_hash": {"synthetic"}, "ports": {ports}}
		req := httptest.NewRequest(http.MethodPost, "/admin/passwords", strings.NewReader(fields.Encode()))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		req.Header.Set("Authorization", "Bearer synthetic-token")
		resp := httptest.NewRecorder()
		mux.ServeHTTP(resp, req)
		if resp.Code != http.StatusBadRequest {
			t.Fatalf("invalid ports %q: got status %d", ports, resp.Code)
		}
		if len(db.Passwords) != 0 || serverWrapKeys.Count() != 0 {
			t.Fatal("invalid request changed subscription state")
		}
	}
	fields := url.Values{"vk_hash": {"synthetic"}, "ports": {"1,2,65535"}}
	req := httptest.NewRequest(http.MethodPost, "/admin/passwords", strings.NewReader(fields.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "Bearer synthetic-token")
	resp := httptest.NewRecorder()
	mux.ServeHTTP(resp, req)
	if resp.Code != http.StatusOK || len(db.Passwords) != 1 {
		t.Fatal("valid ports were rejected")
	}
}

func TestSubscriptionPortsHandlesLegacyData(t *testing.T) {
	for _, value := range []string{"", "1,2,65535"} {
		parts, ok := subscriptionPorts(value)
		if !ok || len(parts) != 3 {
			t.Fatalf("valid ports %q rejected", value)
		}
	}
	for _, value := range []string{"broken", "1,2", "1,2,0", "1,2,65536", "1,2,3,4", "1, 2,3"} {
		if _, ok := subscriptionPorts(value); ok {
			t.Fatalf("invalid legacy ports %q accepted", value)
		}
	}
}
