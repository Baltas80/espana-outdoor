package main

import (
    "context"
    "encoding/json"
    "errors"
    "io"
    "net/http"
    "strings"
    "time"
    "unicode"
    "unicode/utf8"

    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
)

var errCommunityProfileNotFound = errors.New("community profile not found")

type communityProfile struct {
    ID          string    `json:"id"`
    DisplayName string    `json:"displayName,omitempty"`
    Email       string    `json:"email,omitempty"`
    CreatedAt   time.Time `json:"createdAt"`
}

type profileStore interface {
    upsert(context.Context, string, string, string) (communityProfile, error)
    updateDisplayName(context.Context, string, string) (communityProfile, error)
}

type postgresProfileStore struct {
    db *pgxpool.Pool
}

func (s *postgresProfileStore) upsert(ctx context.Context, subject, email, displayName string) (communityProfile, error) {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()

    const query = "INSERT INTO community_profiles (subject, email, display_name) " +
        "VALUES ($1, NULLIF($2, ''), NULLIF($3, '')) " +
        "ON CONFLICT (subject) DO UPDATE SET " +
        "email = COALESCE(NULLIF(EXCLUDED.email, ''), community_profiles.email), " +
        "display_name = COALESCE(community_profiles.display_name, EXCLUDED.display_name), " +
        "updated_at = NOW() " +
        "RETURNING id::text, COALESCE(display_name, ''), COALESCE(email, ''), created_at"

    var profile communityProfile
    err := s.db.QueryRow(ctx, query, subject, email, displayName).Scan(
        &profile.ID,
        &profile.DisplayName,
        &profile.Email,
        &profile.CreatedAt,
    )
    return profile, err
}

func (s *postgresProfileStore) updateDisplayName(ctx context.Context, subject, displayName string) (communityProfile, error) {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()

    const query = "UPDATE community_profiles SET display_name = $2, updated_at = NOW() " +
        "WHERE subject = $1 " +
        "RETURNING id::text, COALESCE(display_name, ''), COALESCE(email, ''), created_at"

    var profile communityProfile
    err := s.db.QueryRow(ctx, query, subject, displayName).Scan(
        &profile.ID,
        &profile.DisplayName,
        &profile.Email,
        &profile.CreatedAt,
    )
    if errors.Is(err, pgx.ErrNoRows) {
        return communityProfile{}, errCommunityProfileNotFound
    }
    return profile, err
}

type updateCommunityProfileRequest struct {
    DisplayName string `json:"displayName"`
}

func (s *server) myProfile(w http.ResponseWriter, r *http.Request) {
    subject, claims, ok := s.authenticateIdentity(w, r)
    if !ok { return }
    if !s.allow(subject) {
        s.writeError(w, http.StatusTooManyRequests, "rate limit exceeded")
        return
    }
    if s.profiles == nil {
        s.writeError(w, http.StatusServiceUnavailable, "community profile service unavailable")
        return
    }

    profile, err := s.profiles.upsert(r.Context(), subject, verifiedEmail(claims), identityDisplayName(claims))
    if err != nil {
        s.log.Error("community profile read failed")
        s.writeError(w, http.StatusServiceUnavailable, "community profile service unavailable")
        return
    }
    s.writeJSON(w, http.StatusOK, profile)
}

func (s *server) updateMyProfile(w http.ResponseWriter, r *http.Request) {
    subject, claims, ok := s.authenticateIdentity(w, r)
    if !ok { return }
    if !s.allow(subject) {
        s.writeError(w, http.StatusTooManyRequests, "rate limit exceeded")
        return
    }
    if s.profiles == nil {
        s.writeError(w, http.StatusServiceUnavailable, "community profile service unavailable")
        return
    }

    decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
    decoder.DisallowUnknownFields()
    var request updateCommunityProfileRequest
    if err := decoder.Decode(&request); err != nil {
        s.writeError(w, http.StatusBadRequest, "invalid profile payload")
        return
    }
    var trailing any
    if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
        s.writeError(w, http.StatusBadRequest, "invalid profile payload")
        return
    }
    displayName, err := normalizeDisplayName(request.DisplayName)
    if err != nil {
        s.writeError(w, http.StatusBadRequest, "displayName must contain 2 to 80 visible characters")
        return
    }

    if _, err := s.profiles.upsert(r.Context(), subject, verifiedEmail(claims), identityDisplayName(claims)); err != nil {
        s.log.Error("community profile provision failed")
        s.writeError(w, http.StatusServiceUnavailable, "community profile service unavailable")
        return
    }
    profile, err := s.profiles.updateDisplayName(r.Context(), subject, displayName)
    if err != nil {
        s.log.Error("community profile update failed")
        s.writeError(w, http.StatusServiceUnavailable, "community profile service unavailable")
        return
    }
    s.writeJSON(w, http.StatusOK, profile)
}

func verifiedEmail(claims map[string]any) string {
    verified, _ := claims["email_verified"].(bool)
    if !verified { return "" }
    email, _ := claims["email"].(string)
    email = strings.TrimSpace(email)
    if len(email) > 254 { return "" }
    return email
}

func identityDisplayName(claims map[string]any) string {
    for _, key := range []string{"name", "preferred_username"} {
        value, _ := claims[key].(string)
        if normalized, err := normalizeDisplayName(value); err == nil {
            return normalized
        }
    }
    return ""
}

func normalizeDisplayName(raw string) (string, error) {
    value := strings.TrimSpace(raw)
    length := utf8.RuneCountInString(value)
    if length < 2 || length > 80 {
        return "", errors.New("display name length is invalid")
    }
    for _, char := range value {
        if unicode.IsControl(char) {
            return "", errors.New("display name contains a control character")
        }
    }
    return value, nil
}
