package main

import "testing"

func TestBotSubscriptionPorts(t *testing.T) {
	for _, tc := range []struct {
		input, want string
		valid       bool
	}{
		{" 1, 2, 65535 ", "1,2,65535", true},
		{"0,1,2", "", false}, {"1,2,65536", "", false},
		{"-1,2,3", "", false}, {"+1,2,3", "", false},
		{"", "", false}, {"1,2", "", false},
	} {
		got, ok := botSubscriptionPorts(tc.input)
		if got != tc.want || ok != tc.valid {
			t.Errorf("input %q: got %q, %v; want %q, %v", tc.input, got, ok, tc.want, tc.valid)
		}
	}
}
