package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"net/url"
	"strings"
	"sync"
	"time"
)

var mobileCaptchaSerial sync.Mutex
var mobileCaptchaLock sync.Mutex
var mobileCaptchaID string
var mobileCaptchaResult chan mobileCaptchaAnswer

type mobileCaptchaAnswer struct {
	ID           string `json:"id"`
	SuccessToken string `json:"success_token"`
	CaptchaKey   string `json:"captcha_key"`
	Cancelled    bool   `json:"cancelled"`
}

func validMobileCaptchaURL(raw string) bool {
	if len(raw) > 16384 || strings.ContainsAny(raw, "\r\n\x00") {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || (u.Port() != "" && u.Port() != "443") {
		return false
	}
	switch strings.ToLower(u.Hostname()) {
	case "vk.com", "vk.ru", "m.vk.com", "m.vk.ru", "api.vk.com", "api.vk.ru", "id.vk.com", "id.vk.ru", "captcha.vk.com", "captcha.vk.ru":
		return true
	}
	return false
}

func handleMobileCaptchaAnswer(raw string) {
	if len(raw) > 32768 {
		return
	}
	var answer mobileCaptchaAnswer
	if json.Unmarshal([]byte(raw), &answer) != nil || len(answer.SuccessToken) > 8192 || strings.ContainsAny(answer.SuccessToken, "\r\n\x00") || len(answer.CaptchaKey) > 512 || strings.ContainsAny(answer.CaptchaKey, "\r\n\x00") {
		return
	}
	mobileCaptchaLock.Lock()
	defer mobileCaptchaLock.Unlock()
	if answer.ID != mobileCaptchaID || mobileCaptchaResult == nil {
		return
	}
	select {
	case mobileCaptchaResult <- answer:
	default:
	}
}

func requestMobileCaptcha(ctx context.Context, challenge *VkCaptchaError) (string, error) {
	if challenge == nil {
		return "", errors.New("missing VK challenge")
	}
	challengeURL := challenge.RedirectURI
	if challengeURL == "" {
		challengeURL = challenge.CaptchaImg
	}
	if !validMobileCaptchaURL(challengeURL) {
		return "", errors.New("unsupported VK challenge")
	}
	mobileCaptchaSerial.Lock()
	defer mobileCaptchaSerial.Unlock()
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	id := uuid.NewString()
	result := make(chan mobileCaptchaAnswer, 1)
	mobileCaptchaLock.Lock()
	mobileCaptchaID = id
	mobileCaptchaResult = result
	mobileCaptchaLock.Unlock()
	defer func() {
		mobileCaptchaLock.Lock()
		mobileCaptchaID = ""
		mobileCaptchaResult = nil
		mobileCaptchaLock.Unlock()
	}()
	record, err := json.Marshal(map[string]string{"id": id, "redirect_uri": challenge.RedirectURI, "captcha_sid": challenge.CaptchaSid, "captcha_img": challenge.CaptchaImg, "captcha_ts": challenge.CaptchaTs, "captcha_attempt": challenge.CaptchaAttempt})
	if err != nil || len(record) > 32700 {
		return "", errors.New("invalid VK challenge")
	}
	fmt.Fprintln(protocolOutput, "CAPTCHA:"+string(record))
	timer := time.NewTimer(180 * time.Second)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case <-timer.C:
		return "", errors.New("VK confirmation expired")
	case answer := <-result:
		value := answer.SuccessToken
		if challenge.RedirectURI == "" {
			value = answer.CaptchaKey
		}
		if answer.Cancelled || value == "" {
			return "", errors.New("VK confirmation cancelled")
		}
		return value, nil
	}
}
