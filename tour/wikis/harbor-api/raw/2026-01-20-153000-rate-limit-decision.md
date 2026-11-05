Captured: 2026-01-20

Decision: deliveries are limited to 100 a minute for each customer endpoint, because one slow customer held up everyone's retries last week. Turned down a global limit, which would have punished the customers who were fine. Review of merge request 44 flagged another bare `return err`, in the limiter.

Feedback: review | here | Wrap returned errors with %w and context. No bare `return err`.
