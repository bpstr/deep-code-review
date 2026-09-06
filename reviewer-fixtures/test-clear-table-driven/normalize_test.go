package normalize

import "testing"

func TestUsername(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "trims surrounding whitespace", in: " Alice ", want: "alice"},
		{name: "normalizes uppercase", in: "BOB", want: "bob"},
		{name: "preserves internal spaces", in: "Mary Jane", want: "mary jane"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Username(tt.in); got != tt.want {
				t.Fatalf("Username(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
