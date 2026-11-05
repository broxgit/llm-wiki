// Package delivery sends webhooks and retries the ones that fail.
package delivery

import "time"

// maxAttempts is how many times one delivery is tried before it goes to the dead letter table.
const maxAttempts = 8

// backoff doubles the wait between attempts, starting at 30 seconds.
func backoff(attempt int) time.Duration {
	return 30 * time.Second << attempt
}
