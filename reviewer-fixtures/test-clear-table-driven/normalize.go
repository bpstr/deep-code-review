package normalize

import "strings"

func Username(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}
