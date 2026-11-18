package main

import (
	"os"
	"testing"
)

// gitSafe adds safe.bareRepository=explicit after whatever the environment carries, once.
func TestGitSafe(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want map[string]string
	}{
		{
			name: "nothing set",
			env:  map[string]string{},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit"},
		},
		{
			name: "another setting stays, and ours follows it",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "someone"},
			want: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "user.name", "GIT_CONFIG_VALUE_0": "someone", "GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "explicit"},
		},
		{
			name: "already there, so not added again",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.barerepository", "GIT_CONFIG_VALUE_0": "explicit"},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_1": ""},
		},
		{
			name: "one that lets any folder pass is overridden",
			env:  map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "all"},
			want: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "explicit"},
		},
		{
			name: "ours, then one that undoes it",
			env: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit",
				"GIT_CONFIG_KEY_1": "safe.bareRepository", "GIT_CONFIG_VALUE_1": "all"},
			want: map[string]string{"GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_2": "safe.bareRepository", "GIT_CONFIG_VALUE_2": "explicit"},
		},
		{
			name: "ours, then an include that could undo it",
			env: map[string]string{"GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit",
				"GIT_CONFIG_KEY_1": "include.path", "GIT_CONFIG_VALUE_1": "/somewhere/else"},
			want: map[string]string{"GIT_CONFIG_COUNT": "3", "GIT_CONFIG_KEY_2": "safe.bareRepository", "GIT_CONFIG_VALUE_2": "explicit"},
		},
		{
			name: "a count that isn't a number starts again",
			env:  map[string]string{"GIT_CONFIG_COUNT": "many"},
			want: map[string]string{"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "safe.bareRepository", "GIT_CONFIG_VALUE_0": "explicit"},
		},
	}
	keys := []string{"GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG_KEY_1", "GIT_CONFIG_VALUE_1", "GIT_CONFIG_KEY_2", "GIT_CONFIG_VALUE_2"}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, k := range keys {
				t.Setenv(k, tt.env[k])
			}
			gitSafe()
			for k, want := range tt.want {
				if got := os.Getenv(k); got != want {
					t.Errorf("%s = %q, want %q", k, got, want)
				}
			}
		})
	}
}
