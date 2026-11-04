package transports

import "testing"

func TestOnlyMessageBridgeTransports(t *testing.T) {
	if err := Init(); err != nil {
		t.Fatal(err)
	}
	if got := Transports(); len(got) != 3 {
		t.Fatalf("expected obfs4, webtunnel and snowflake; got %v", got)
	}
	if Get("obfs4") == nil || Get("webtunnel") == nil || Get("snowflake") == nil {
		t.Fatal("required transport missing")
	}
}
