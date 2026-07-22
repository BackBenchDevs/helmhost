//! Public-API tests for async protocol traits via mocks.

use helmhost_core::{
    BoxFuture, ConnectTarget, Creds, FramebufferCache, ProtocolId, SessionCommand, SessionEvent,
    SessionFactory, SessionHandle, SessionId,
};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

struct MockFactory;

impl SessionFactory for MockFactory {
    fn protocol(&self) -> ProtocolId {
        ProtocolId::RFB
    }

    fn connect(
        &self,
        _target: ConnectTarget,
        _creds: Creds,
    ) -> BoxFuture<'_, Result<SessionHandle, String>> {
        Box::pin(async {
            let (cmd_tx, mut cmd_rx) = mpsc::channel(8);
            let (ev_tx, ev_rx) = mpsc::channel(8);
            tokio::spawn(async move {
                while let Some(cmd) = cmd_rx.recv().await {
                    match cmd {
                        SessionCommand::Close => {
                            let _ = ev_tx.send(SessionEvent::Disconnected).await;
                            break;
                        }
                        SessionCommand::Pointer(_) | SessionCommand::Key(_) => {}
                        SessionCommand::CutText(_)
                        | SessionCommand::RequestUpdate { .. }
                        | SessionCommand::EnableContinuousUpdates { .. }
                        | SessionCommand::SetDesktopSize { .. } => {}
                    }
                }
            });
            Ok(SessionHandle {
                id: SessionId(1),
                width: 640,
                height: 480,
                events: ev_rx,
                commands: cmd_tx,
                framebuffer: Arc::new(Mutex::new(FramebufferCache::new(640, 480))),
            })
        })
    }
}

#[tokio::test]
async fn factory_returns_session_handle() {
    let factory = MockFactory;
    let handle = factory
        .connect(
            ConnectTarget {
                host: "127.0.0.1".into(),
                port: 5900,
            },
            Creds::default(),
        )
        .await
        .expect("connect");
    assert_eq!(handle.id, SessionId(1));
    assert_eq!((handle.width, handle.height), (640, 480));
    assert_eq!(factory.protocol(), ProtocolId::RFB);
    handle.close().await.unwrap();
}

#[tokio::test]
async fn mock_session_close_emits_disconnected() {
    let factory = MockFactory;
    let mut handle = factory
        .connect(
            ConnectTarget {
                host: "127.0.0.1".into(),
                port: 5900,
            },
            Creds::default(),
        )
        .await
        .unwrap();
    handle.send(SessionCommand::Close).await.unwrap();
    let ev = handle.events.recv().await.unwrap();
    assert_eq!(ev, SessionEvent::Disconnected);
}
