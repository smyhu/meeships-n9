/* GameNet - shared 1v1 Wi-Fi link for the N9 MeeGames (games-common).
 * Copyright (c) 2026 smyhu. MIT License (see LICENSE).
 * Designed and written by Claude (Anthropic) together with smyhu.
 *
 * Use from QML (registered as "MeeGames 1.0" / GameNet):
 *   GameNet { id: net; gameId: "meeships"; name: "N9-58" }
 *   net.start()          listen for invites + announce this phone on the Wi-Fi (UDP broadcast)
 *   net.peers            JSON text: [{"name":..,"ip":..,"port":..,"busy":false}, ...] (phones running the same game)
 *   net.invite(ip, port) ask a phone to play; answer arrives as accepted() / declined(reason)
 *   invited(name, ip)    somebody asks us; answer with net.accept() or net.decline()
 *   net.send(text)       one line of text (the game's own message, usually JSON) to the other phone
 *   message(text)        a line from the other phone (every line arrives exactly once, in order)
 *   linkLost()           the connection dropped: the match is kept, GameNet reconnects by itself
 *   resumed()            connection back; lines sent meanwhile are delivered now
 *   peerLeft(reason)     "bye" (other side left) or "lost" (no reconnect within resumeSeconds)
 *   net.leave()          end the match;  net.stop()  stop everything (leaving the Wi-Fi screen)
 *
 * Wire format (TCP, UTF-8 lines):
 *   HELLO <gameId> <proto> <session> <lastSeq> <name>   (session "-" = new match; else resume)
 *   ACCEPT <lastSeq> <name> | DECLINE <reason> | MSG <seq> <text> | PING | PONG | BYE
 * Every MSG has a sequence number; after a reconnect both sides resend what the other did not get.
 * Fast path: every MSG is also sent as a UDP datagram to the other phone (port 45454) and repeated
 * every 300 ms until confirmed ("ACK <seq>" over TCP, "MEEACK" over UDP). Whichever copy arrives
 * first is used, so one lost Wi-Fi packet no longer waits for a slow TCP retransmission.
 *   UDP: "MEEMSG <token> <session> <seq> <text>" | "MEEACK <token> <session> <seq>"
 * Discovery (UDP broadcast, port 45454): "MEEGAMES 2 <gameId> <tcpPort> <busy> <token> <name>"
 */
#ifndef GAMENET_H
#define GAMENET_H
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QMap>
#include <QtCore/QTime>
#include <QtCore/QTimer>
#include <QtNetwork/QTcpServer>
#include <QtNetwork/QTcpSocket>
#include <QtNetwork/QUdpSocket>

class GameNet : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString gameId READ gameId WRITE setGameId)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString localAddress READ localAddress NOTIFY localAddressChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool reconnecting READ reconnecting NOTIFY reconnectingChanged)
    Q_PROPERTY(int resumeSeconds READ resumeSeconds WRITE setResumeSeconds)
    Q_PROPERTY(bool inviting READ inviting NOTIFY invitingChanged)
    Q_PROPERTY(bool initiator READ initiator NOTIFY connectedChanged)
    Q_PROPERTY(QString peerName READ peerName NOTIFY connectedChanged)
    Q_PROPERTY(QString peers READ peers NOTIFY peersChanged)
public:
    explicit GameNet(QObject *parent = 0);
    ~GameNet();

    QString gameId() const { return m_gameId; }
    void setGameId(const QString &g) { m_gameId = g; }
    QString name() const { return m_name; }
    void setName(const QString &n);
    QString localAddress() const { return m_localAddress; }
    bool active() const { return m_active; }
    bool connected() const { return m_connected; }          // a match is on (also while reconnecting)
    bool reconnecting() const { return m_connected && !m_link; }
    int resumeSeconds() const { return m_resumeSec; }
    void setResumeSeconds(int s) { m_resumeSec = s > 5 ? s : 5; }
    bool inviting() const { return m_out != 0 && !m_connected; }
    bool initiator() const { return m_initiator; }
    QString peerName() const { return m_peerName; }
    QString peers() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void invite(const QString &ip, int port = 45455);
    Q_INVOKABLE void cancelInvite();
    Q_INVOKABLE void accept();
    Q_INVOKABLE void decline();
    Q_INVOKABLE void send(const QString &text);
    Q_INVOKABLE void leave();

signals:
    void nameChanged();
    void localAddressChanged();
    void activeChanged();
    void connectedChanged();
    void reconnectingChanged();
    void invitingChanged();
    void peersChanged();
    void invited(const QString &name, const QString &ip);
    void inviteCancelled();
    void accepted();
    void declined(const QString &reason);
    void message(const QString &text);
    void linkLost();
    void resumed();
    void peerLeft(const QString &reason);
    void error(const QString &text);

private slots:
    void onNewConnection();
    void onUdpReady();
    void onBeacon();
    void onOutConnected();
    void onOutError();
    void onReadyRead();
    void onDisconnected();
    void onHeartbeat();
    void onRedial();
    void onUdpResend();

private:
    struct Peer { QString name; QString ip; int port; bool busy; QTime seen; };
    void updateLocalAddress();
    void writeLine(QTcpSocket *s, const QString &line);
    void handleLine(QTcpSocket *s, const QString &line);
    void setConnected(QTcpSocket *s, const QString &peer, bool initiator);
    void attachLink(QTcpSocket *s, int peerLastSeq);
    void suspend();
    void dropSocket(QTcpSocket *s);
    void endMatch(const QString &reason, bool notify);
    QTcpSocket *dial(const QString &ip, int port);
    void deliver(int seq, const QString &text);
    void sendUdpCopy(int seq);
    void gotAck(int seq);

    QString m_gameId, m_name, m_localAddress, m_peerName, m_token, m_pendingName;
    bool m_active, m_connected, m_initiator, m_redialing;
    int m_port, m_resumeSec;
    QTcpServer *m_server;
    QUdpSocket *m_udp;
    QTimer m_beacon, m_heart, m_redial, m_udpResend;
    QTcpSocket *m_link;      // the live match connection (0 while reconnecting)
    QTcpSocket *m_out;       // our outgoing invite or redial (before ACCEPT)
    QTcpSocket *m_pending;   // incoming invite waiting for accept()/decline()
    QTime m_lastRx, m_lostAt;
    QMap<QString, Peer> m_peers;
    // match session: survives a dropped connection
    QString m_session, m_peerIp;
    int m_peerPort;
    QStringList m_outbox;    // every MSG text sent in this match; seq = index + 1
    int m_rxSeq;             // last MSG seq received
    int m_peerAck;           // last of our MSG seq the other phone confirmed
    QMap<int, QString> m_early;   // UDP copies that arrived before the line in front of them
};
#endif
