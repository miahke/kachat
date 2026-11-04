package main

import (
	"bytes"
	"fmt"
	"strings"
	"testing"
)

func TestMobileConfigRefusesOpenProxyAndMissingSecrets(t *testing.T) {
	for _, text := range []string{
		`{}`,
		`{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","password":"synthetic-password","port":1080,"username":"","socksPassword":"test-password"}`,
		`{"mode":"shell","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}`,
	} {
		if _, err := readMobileConfig(strings.NewReader(text + "\n")); err == nil {
			t.Fatal("invalid configuration accepted")
		}
	}
}

func TestMobileConfigProducesOnlyLoopbackAuthenticatedSocksWithTwoWorkers(t *testing.T) {
	cfg, err := readMobileConfig(strings.NewReader(`{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}` + "\n"))
	if err != nil {
		t.Fatal(err)
	}
	args := cfg.args()
	joined := strings.Join(args, " ")
	for _, want := range []string{"-mode socks", "-n 2", "-socks 127.0.0.1:1080", "-socks-auth=true"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("configuration missing %s", want)
		}
	}
}

func TestMobileConfigBoundsInputAndRejectsUnknownFields(t *testing.T) {
	for _, text := range []string{strings.Repeat("a", 65537), `{"arbitraryFlag":"notls"}`} {
		if _, err := readMobileConfig(strings.NewReader(text + "\n")); err == nil {
			t.Fatal("unexpected input accepted")
		}
	}
}

func TestMissingDeviceIdentityDoesNotShareAServerPeerAcrossClients(t *testing.T) {
	text := `{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}`
	a, err := readMobileConfig(strings.NewReader(text))
	if err != nil {
		t.Fatal(err)
	}
	b, err := readMobileConfig(strings.NewReader(text))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(a.args(), " ") == strings.Join(b.args(), " ") {
		t.Fatal("independent clients reuse server device identity")
	}
}

func TestMobileStatusOnlyEmitsKnownRedactedStages(t *testing.T) {
	previous, active := protocolOutput, mobileProtocolActive
	defer func() { protocolOutput = previous; mobileProtocolActive = active }()
	var output bytes.Buffer
	protocolOutput = &output
	mobileProtocolActive = true
	emitMobileStage("TURN_READY")
	emitMobileStage("synthetic-secret-not-a-stage")
	if output.String() != "STAGE:TURN_READY\n" {
		t.Fatal("unexpected status output")
	}
}

func TestMobileConfigPreservesMultipleHashesAndSelectedWorkers(t *testing.T) {
	cfg, err := readMobileConfig(strings.NewReader(`{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash-one,synthetic-call-hash-two","workers":54,"password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}`))
	if err != nil {
		t.Fatal(err)
	}
	args := strings.Join(cfg.args(), " ")
	if !strings.Contains(args, "-n 54") || !strings.Contains(args, "synthetic-call-hash-one,synthetic-call-hash-two") {
		t.Fatal("lost worker selection or hashes")
	}
}

func TestMobileWorkerCountBoundsAndSmallSelections(t *testing.T) {
	for _, workers := range []int{0, -1, 109} {
		text := fmt.Sprintf(`{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","workers":%d,"password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}`, workers)
		if _, err := readMobileConfig(strings.NewReader(text)); err == nil {
			t.Fatal("invalid worker count accepted")
		}
	}
	for _, workers := range []int{1, 2, 9, 108} {
		text := fmt.Sprintf(`{"mode":"wg","peer":"192.0.2.1:56001","hash":"synthetic-call-hash","workers":%d,"password":"synthetic-password","port":1080,"username":"test-user","socksPassword":"test-password"}`, workers)
		cfg, err := readMobileConfig(strings.NewReader(text))
		if err != nil || !strings.Contains(strings.Join(cfg.args(), " "), fmt.Sprintf("-n %d ", workers)) {
			t.Fatal("worker selection lost")
		}
	}
}

func TestMobileStatisticsSupportsConfiguredWorkerRange(t *testing.T) {
	previous, active := protocolOutput, mobileProtocolActive
	defer func() { protocolOutput = previous; mobileProtocolActive = active }()
	var output bytes.Buffer
	protocolOutput = &output
	mobileProtocolActive = true
	emitMobileStatistics(108, 1, 2)
	emitMobileStatistics(109, 1, 2)
	if output.String() != "STATS:108:1:2\n" {
		t.Fatal("invalid worker telemetry bound")
	}
}
