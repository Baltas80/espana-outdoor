package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidUsername(t *testing.T) {
	valid := []string{"abc", "alex_1", "senderista.82", "a-hello", "0user"}
	for _, value := range valid {
		if !validUsername(value) { t.Errorf("expected username %q to be valid", value) }
	}
	invalid := []string{"", "ab", "ALEX", "_alex", ".alex", "alex!", "alex name", "this_username_is_way_too_long"}
	for _, value := range invalid {
		if validUsername(value) { t.Errorf("expected username %q to be invalid", value) }
	}
}

func TestValidateProfile(t *testing.T) {
	valid := profile{DisplayName: "Alex Senderista", Username: "alex_1", HomeArea: "Córdoba", Bio: "Me gusta caminar"}
	if message := validateProfile(valid); message != "" { t.Fatalf("unexpected validation error: %s", message) }

	cases := []struct{name string; value profile}{
		{name: "display name too short", value: profile{DisplayName:"A", Username:"alex_1"}},
		{name: "invalid username", value: profile{DisplayName:"Alex", Username:"not valid"}},
		{name: "long home area", value: profile{DisplayName:"Alex", Username:"alex_1", HomeArea:strings.Repeat("x", 81)}},
		{name: "long bio", value: profile{DisplayName:"Alex", Username:"alex_1", Bio:strings.Repeat("x", 161)}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if message := validateProfile(tc.value); message == "" { t.Fatal("expected validation failure") }
		})
	}
}

func TestDecodeJSONRejectsUnknownFieldsAndTrailingData(t *testing.T) {
	for _, body := range []string{
		`{"displayName":"Alex","username":"alex_1","isAdmin":true}`,
		`{"displayName":"Alex","username":"alex_1"} garbage`,
		`{"displayName":"Alex","username":"alex_1"} {"displayName":"Other"}`,
	} {
		req := httptest.NewRequest(http.MethodPut, "/v1/me/profile", bytes.NewBufferString(body))
		if err := decodeJSON(httptest.NewRecorder(), req, &profile{}, 8192); err == nil {
			t.Errorf("expected strict JSON decode error for %s", body)
		}
	}
}

func TestProfileJSONContract(t *testing.T) {
	p := profile{DisplayName:"Alex", Username:"alex_1", HomeArea:"Córdoba", Bio:"Senderismo"}
	data, err := json.Marshal(p)
	if err != nil { t.Fatal(err) }
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil { t.Fatal(err) }
	for _, field := range []string{"displayName", "username", "homeArea", "bio"} {
		if _, ok := decoded[field]; !ok { t.Errorf("missing JSON field %q", field) }
	}
}
