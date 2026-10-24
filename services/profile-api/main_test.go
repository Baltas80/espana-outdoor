package main

import "testing"

func TestNormalizeAndValidateProfile(t *testing.T) {
	input := profileInput{
		DisplayName: "  Alex Senderista  ",
		Username:    " Alex_1 ",
		HomeArea:    " Córdoba ",
		Bio:         " Rutas y naturaleza ",
	}
	got, message := normalizeAndValidate(input)
	if message != "" {
		t.Fatalf("expected valid profile, got error %q", message)
	}
	if got.DisplayName != "Alex Senderista" || got.Username != "alex_1" {
		t.Fatalf("profile was not normalized: %#v", got)
	}
	if got.HomeArea != "Córdoba" || got.Bio != "Rutas y naturaleza" {
		t.Fatalf("optional fields were not normalized: %#v", got)
	}
}

func TestNormalizeAndValidateRejectsInvalidUsername(t *testing.T) {
	_, message := normalizeAndValidate(profileInput{
		DisplayName: "Alex",
		Username:    "x",
	})
	if message == "" {
		t.Fatal("expected invalid username to be rejected")
	}
}

func TestNormalizeAndValidateCountsUnicodeRunes(t *testing.T) {
	_, message := normalizeAndValidate(profileInput{
		DisplayName: "Á",
		Username:    "alex_1",
	})
	if message == "" {
		t.Fatal("expected a one-rune display name to be rejected")
	}
}
