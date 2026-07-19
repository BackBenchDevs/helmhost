//! Public-API tests for protocol traits via mocks (P1-T02).

use helmhost_core::{
    ConnectTarget, Creds, FrameSink, KeyEvent, PointerEvent, ProtocolId, Rect, RemoteSession,
    SessionFactory, SessionId, SessionStatus,
};

struct NullSink;

impl FrameSink for NullSink {
    fn on_desktop_resize(&mut self, _w: u32, _h: u32) {}
    fn on_damage(&mut self, _rect: Rect, _rgba: &[u8]) {}
}

struct MockSession {
    id: SessionId,
}

impl RemoteSession for MockSession {
    fn session_id(&self) -> SessionId {
        self.id
    }

    fn desktop_size(&self) -> (u32, u32) {
        (640, 480)
    }

    fn send_pointer(&mut self, _ev: PointerEvent) -> Result<(), String> {
        Ok(())
    }

    fn send_key(&mut self, _ev: KeyEvent) -> Result<(), String> {
        Ok(())
    }

    fn poll(&mut self, _sink: &mut dyn FrameSink) -> Result<SessionStatus, String> {
        Ok(SessionStatus::Ok)
    }

    fn close(&mut self) {}
}

struct MockFactory;

impl SessionFactory for MockFactory {
    fn protocol(&self) -> ProtocolId {
        ProtocolId::RFB
    }

    fn connect(
        &self,
        _target: &ConnectTarget,
        _creds: &Creds,
    ) -> Result<Box<dyn RemoteSession>, String> {
        Ok(Box::new(MockSession { id: SessionId(1) }))
    }
}

#[test]
fn factory_returns_boxed_remote_session() {
    let factory = MockFactory;
    let session = factory
        .connect(
            &ConnectTarget {
                host: "127.0.0.1".into(),
                port: 5900,
            },
            &Creds::default(),
        )
        .expect("connect");
    assert_eq!(session.session_id(), SessionId(1));
    assert_eq!(session.desktop_size(), (640, 480));
    assert_eq!(factory.protocol(), ProtocolId::RFB);
}

#[test]
fn mock_session_poll_ok() {
    let mut session = MockSession { id: SessionId(2) };
    let mut sink = NullSink;
    assert_eq!(session.poll(&mut sink).unwrap(), SessionStatus::Ok);
    session.close();
}
