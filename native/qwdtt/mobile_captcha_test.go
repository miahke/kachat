package main

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestMobileCaptchaURLPolicy(t *testing.T) {
	for _, value := range []string{"https://api.vk.ru/captcha.php?sid=synthetic", "https://id.vk.com/not_robot_captcha?session_token=synthetic"} {
		if !validMobileCaptchaURL(value) {
			t.Fatal("official URL rejected")
		}
	}
	for _, value := range []string{"http://vk.com/captcha", "https://vk.com.evil.test/", "https://evil@vk.com/", "https://vk.com:8443/", "https://evil.vk.com/", "file:///captcha"} {
		if validMobileCaptchaURL(value) {
			t.Fatal("unsafe URL accepted")
		}
	}
}

func TestMobileCaptchaCorrelatesAndCancels(t *testing.T) {
	old := protocolOutput
	defer func() { protocolOutput = old }()
	output := new(bytes.Buffer)
	protocolOutput = output
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	go func() {
		_, err := requestMobileCaptcha(ctx, &VkCaptchaError{RedirectURI: "https://id.vk.com/captcha?session_token=synthetic", CaptchaSid: "synthetic"})
		result <- err
	}()
	var id string
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		mobileCaptchaLock.Lock()
		id = mobileCaptchaID
		mobileCaptchaLock.Unlock()
		if id != "" {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if id == "" {
		cancel()
		t.Fatal("challenge was not registered")
	}
	handleMobileCaptchaAnswer(`{"id":"stale","success_token":"synthetic"}`)
	select {
	case <-result:
		t.Fatal("stale answer accepted")
	default:
	}
	cancel()
	if err := <-result; err == nil {
		t.Fatal("cancel ignored")
	}
	line := strings.TrimPrefix(strings.TrimSpace(output.String()), "CAPTCHA:")
	var data map[string]string
	if json.Unmarshal([]byte(line), &data) != nil || data["id"] != id {
		t.Fatal("invalid protocol record")
	}
	mobileCaptchaLock.Lock()
	active := mobileCaptchaID
	mobileCaptchaLock.Unlock()
	if active != "" {
		t.Fatal("cancelled challenge retained")
	}
}

func TestMobileImageCaptchaReturnsOnlyUserKey(t *testing.T) {
	old := protocolOutput
	defer func() { protocolOutput = old }()
	protocolOutput = new(bytes.Buffer)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	result := make(chan string, 1)
	failed := make(chan error, 1)
	go func() {
		value, err := requestMobileCaptcha(ctx, &VkCaptchaError{CaptchaImg: "https://api.vk.ru/captcha.php?sid=synthetic", CaptchaSid: "synthetic"})
		result <- value
		failed <- err
	}()
	var id string
	for ctx.Err() == nil {
		mobileCaptchaLock.Lock()
		id = mobileCaptchaID
		mobileCaptchaLock.Unlock()
		if id != "" {
			break
		}
		time.Sleep(time.Millisecond)
	}
	data, _ := json.Marshal(map[string]string{"id": id, "captcha_key": "synthetic-answer"})
	handleMobileCaptchaAnswer(string(data))
	if value := <-result; value != "synthetic-answer" {
		t.Fatal("image answer lost")
	}
	if err := <-failed; err != nil {
		t.Fatal(err)
	}
}
