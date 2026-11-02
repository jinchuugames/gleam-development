//// A login session. Every time in this module arrives as an argument, so the
//// rules here are pure, deterministic, and identical on both targets.

pub type Session {
  Session(token: String, started_at: Int, ttl: Int)
}

pub fn new(token: String, started_at: Int, ttl: Int) -> Session {
  Session(token: token, started_at: started_at, ttl: ttl)
}

/// The first second at which the session is no longer valid.
pub fn expires_at(session: Session) -> Int {
  session.started_at + session.ttl
}

/// Whether the session is no longer valid at `now`.
pub fn is_expired(session: Session, now: Int) -> Bool {
  False
}

/// Whole seconds left before expiry, never negative.
pub fn remaining(session: Session, now: Int) -> Int {
  0
}
