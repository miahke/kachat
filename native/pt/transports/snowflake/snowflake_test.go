package snowflake

import (
	pt "gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/goptlib"
	sf "gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/v2/client/lib"
	"testing"
)

func TestSnowflakeTorBrowserArguments(t *testing.T) {
	factory, err := new(Transport).ClientFactory(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	args := pt.Args{}
	args.Add("url", "https://broker.example.invalid/")
	args.Add("fronts", "front1.example.invalid,front2.example.invalid")
	args.Add("ice", "stun:stun.example.invalid:3478")
	args.Add("fingerprint", "2B280B23E1107BB62ABFC40DDCC8824814F80A72")
	args.Add("utls-imitate", "hellorandomizedalpn")
	parsed, err := factory.ParseArgs(&args)
	if err != nil {
		t.Fatal(err)
	}
	config := parsed.(sf.ClientConfig)
	if len(config.FrontDomains) != 2 || len(config.ICEAddresses) != 1 || config.BridgeFingerprint != "2B280B23E1107BB62ABFC40DDCC8824814F80A72" || config.UTLSClientID != "hellorandomizedalpn" {
		t.Fatal("Snowflake configuration was not passed to real WebRTC client")
	}
	args.Add("max", "invalid")
	if _, err := factory.ParseArgs(&args); err == nil {
		t.Fatal("invalid pool size accepted")
	}
}
