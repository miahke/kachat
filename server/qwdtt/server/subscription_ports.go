package main

import (
	"strconv"
	"strings"
)

// subscriptionPorts validates new requests and safely reads older records.
func subscriptionPorts(raw string) ([]string, bool) {
	if raw == "" {
		raw = "56000,56001,9000"
	}
	parts := strings.Split(raw, ",")
	if len(parts) != 3 {
		return nil, false
	}
	for _, part := range parts {
		if part == "" {
			return nil, false
		}
		for _, char := range part {
			if char < '0' || char > '9' {
				return nil, false
			}
		}
		n, err := strconv.Atoi(part)
		if err != nil || n < 1 || n > 65535 {
			return nil, false
		}
	}
	return parts, true
}

func botSubscriptionPorts(raw string) (string, bool) {
	parts := strings.Split(raw, ",")
	if len(parts) != 3 {
		return "", false
	}
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	normalized := strings.Join(parts, ",")
	_, ok := subscriptionPorts(normalized)
	if !ok {
		return "", false
	}
	return normalized, true
}
