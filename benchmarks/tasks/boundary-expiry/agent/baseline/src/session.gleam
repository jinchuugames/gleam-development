pub type Session {
  Session(token: String, started_at: Int, ttl: Int)
}

pub fn new(token: String, started_at: Int, ttl: Int) -> Session {
  Session(token: token, started_at: started_at, ttl: ttl)
}

pub fn expires_at(session: Session) -> Int {
  session.started_at + session.ttl
}

pub fn is_expired(session: Session, now: Int) -> Bool {
  now > expires_at(session)
}

pub fn remaining(session: Session, now: Int) -> Int {
  expires_at(session) - now
}
