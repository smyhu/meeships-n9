/* GameNet - shared 1v1 Wi-Fi link for the N9 MeeGames (games-common). See gamenet.h.
 * Copyright (c) 2026 smyhu. MIT License (see LICENSE). */
#include "gamenet.h"
#include <QtCore/QDateTime>
#include <QtNetwork/QNetworkInterface>
#include <QtNetwork/QHostAddress>

static const quint16 DISCOVERY_PORT = 45454;
static const quint16 FIRST_TCP_PORT = 45455;
static const char *PROTO = "2";
static const int PING_MS = 3000;
static const int SILENCE_MS = 12000;   // no data for this long = connection lost (then reconnect)
static const int REDIAL_MS = 3000;
static const int UDP_RESEND_MS = 300;

static QString jsonEscape(const QString &s)
{
    QString o;
    for (int i = 0; i < s.length(); i++) {
        QChar c = s.at(i);
        if (c == '"' || c == '\\') { o += '\\'; o += c; }
        else if (c.unicode() < 32) o += ' ';
        else o += c;
    }
    return o;
}

static QString cleanIp(const QHostAddress &a)
{
    QString ip = a.toString();
    if (ip.startsWith("::ffff:")) ip = ip.mid(7);
    return ip;
}

GameNet::GameNet(QObject *parent)
    : QObject(parent), m_gameId("game"), m_name("N9"), m_active(false), m_connected(false),
      m_initiator(false), m_redialing(false), m_port(0), m_resumeSec(90), m_server(0), m_udp(0),
      m_link(0), m_out(0), m_pending(0), m_peerPort(FIRST_TCP_PORT), m_rxSeq(0), m_peerAck(0)
{
    qsrand(QDateTime::currentDateTime().toTime_t() ^ (quintptr)this);
    m_token = QString::number(qrand() % 900000 + 100000);
    m_beacon.setInterval(1500);
    m_heart.setInterval(PING_MS);
    m_redial.setInterval(REDIAL_MS);
    connect(&m_beacon, SIGNAL(timeout()), this, SLOT(onBeacon()));
    connect(&m_heart, SIGNAL(timeout()), this, SLOT(onHeartbeat()));
    connect(&m_redial, SIGNAL(timeout()), this, SLOT(onRedial()));
    m_udpResend.setInterval(UDP_RESEND_MS);
    connect(&m_udpResend, SIGNAL(timeout()), this, SLOT(onUdpResend()));
    updateLocalAddress();
}

GameNet::~GameNet()
{
    stop();
}

void GameNet::setName(const QString &n)
{
    QString c = n.simplified();
    if (c.isEmpty() || c == m_name) return;
    m_name = c.left(16);
    emit nameChanged();
}

void GameNet::updateLocalAddress()
{
    QString best, any;
    foreach (const QNetworkInterface &ifc, QNetworkInterface::allInterfaces()) {
        if (!(ifc.flags() & QNetworkInterface::IsUp) || (ifc.flags() & QNetworkInterface::IsLoopBack)) continue;
        foreach (const QNetworkAddressEntry &e, ifc.addressEntries()) {
            if (e.ip().protocol() != QAbstractSocket::IPv4Protocol) continue;
            if (ifc.name().startsWith("wlan") && best.isEmpty()) best = e.ip().toString();
            if (any.isEmpty() && (ifc.flags() & QNetworkInterface::CanBroadcast)) any = e.ip().toString();
        }
    }
    QString a = best.isEmpty() ? any : best;
    if (a != m_localAddress) { m_localAddress = a; emit localAddressChanged(); }
}

QString GameNet::peers() const
{
    QString o = "[";
    bool first = true;
    foreach (const Peer &p, m_peers) {
        if (!first) o += ",";
        first = false;
        o += QString("{\"name\":\"%1\",\"ip\":\"%2\",\"port\":%3,\"busy\":%4}")
                .arg(jsonEscape(p.name), p.ip).arg(p.port).arg(p.busy ? "true" : "false");
    }
    return o + "]";
}

void GameNet::start()
{
    if (m_active) return;
    m_server = new QTcpServer(this);
    m_port = 0;
    for (quint16 p = FIRST_TCP_PORT; p < FIRST_TCP_PORT + 6; p++)
        if (m_server->listen(QHostAddress::Any, p)) { m_port = p; break; }
    if (!m_port) emit error("listen");
    connect(m_server, SIGNAL(newConnection()), this, SLOT(onNewConnection()));
    m_udp = new QUdpSocket(this);
    if (!m_udp->bind(QHostAddress::Any, DISCOVERY_PORT, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint))
        emit error("discovery");
    connect(m_udp, SIGNAL(readyRead()), this, SLOT(onUdpReady()));
    m_active = true;
    emit activeChanged();
    onBeacon();
    m_beacon.start();
}

void GameNet::stop()
{
    leave();
    cancelInvite();
    if (m_pending) decline();
    m_beacon.stop();
    m_heart.stop();
    m_redial.stop();
    if (m_server) { m_server->close(); m_server->deleteLater(); m_server = 0; }
    if (m_udp) { m_udp->close(); m_udp->deleteLater(); m_udp = 0; }
    if (!m_peers.isEmpty()) { m_peers.clear(); emit peersChanged(); }
    if (m_active) { m_active = false; emit activeChanged(); }
}

// ---------------- discovery ----------------
void GameNet::onBeacon()
{
    updateLocalAddress();
    if (m_udp && m_port) {
        QByteArray d = QString("MEEGAMES 2 %1 %2 %3 %4 %5").arg(m_gameId).arg(m_port)
                .arg((m_connected || m_pending || m_out) ? 1 : 0).arg(m_token).arg(m_name).toUtf8();
        QList<QHostAddress> sent;
        foreach (const QNetworkInterface &ifc, QNetworkInterface::allInterfaces()) {
            if (!(ifc.flags() & QNetworkInterface::IsUp) || !(ifc.flags() & QNetworkInterface::CanBroadcast)
                    || (ifc.flags() & QNetworkInterface::IsLoopBack)) continue;
            foreach (const QNetworkAddressEntry &e, ifc.addressEntries()) {
                if (e.ip().protocol() != QAbstractSocket::IPv4Protocol || e.broadcast().isNull()) continue;
                if (sent.contains(e.broadcast())) continue;
                sent << e.broadcast();
                m_udp->writeDatagram(d, e.broadcast(), DISCOVERY_PORT);
            }
        }
        if (sent.isEmpty()) m_udp->writeDatagram(d, QHostAddress::Broadcast, DISCOVERY_PORT);
    }
    // forget phones not heard for 5 s
    bool changed = false;
    QMap<QString, Peer>::iterator it = m_peers.begin();
    while (it != m_peers.end()) {
        if (it.value().seen.elapsed() > 5000) { it = m_peers.erase(it); changed = true; }
        else ++it;
    }
    if (changed) emit peersChanged();
}

void GameNet::onUdpReady()
{
    while (m_udp && m_udp->hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(m_udp->pendingDatagramSize()));
        QHostAddress from;
        m_udp->readDatagram(d.data(), d.size(), &from);
        QString s = QString::fromUtf8(d.constData(), d.size());
        QStringList f = s.split(' ');
        if ((f[0] == "MEEMSG" || f[0] == "MEEACK") && f.size() >= 4) {
            if (f[1] == m_token || !m_connected || f[2] != m_session) continue;
            if (f[0] == "MEEACK") gotAck(f[3].toInt());
            else deliver(f[3].toInt(), s.section(' ', 4));
            continue;
        }
        if (f.size() < 7 || f[0] != "MEEGAMES" || f[1] != PROTO) continue;
        if (f[2] != m_gameId || f[5] == m_token) continue;
        Peer p;
        p.ip = cleanIp(from);
        p.port = f[3].toInt();
        p.busy = f[4] == "1";
        p.name = s.section(' ', 6).left(16);
        p.seen.start();
        QString key = p.ip + ":" + QString::number(p.port);
        bool changed = !m_peers.contains(key) || m_peers[key].name != p.name || m_peers[key].busy != p.busy;
        m_peers[key] = p;
        if (changed) emit peersChanged();
    }
}

// ---------------- connections ----------------
QTcpSocket *GameNet::dial(const QString &ip, int port)
{
    QTcpSocket *s = new QTcpSocket(this);
    connect(s, SIGNAL(connected()), this, SLOT(onOutConnected()));
    connect(s, SIGNAL(error(QAbstractSocket::SocketError)), this, SLOT(onOutError()));
    connect(s, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(s, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    s->connectToHost(ip, quint16(port > 0 ? port : FIRST_TCP_PORT));
    s->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    return s;
}

void GameNet::invite(const QString &ip, int port)
{
    if (m_connected || m_out) return;
    m_session = QString::number(qrand() % 90000000 + 10000000);
    m_peerIp = ip.trimmed();
    m_peerPort = port > 0 ? port : FIRST_TCP_PORT;
    m_redialing = false;
    m_out = dial(m_peerIp, m_peerPort);
    emit invitingChanged();
}

void GameNet::cancelInvite()
{
    if (!m_out || m_redialing) return;
    QTcpSocket *s = m_out;
    m_out = 0;
    if (s->state() == QAbstractSocket::ConnectedState) writeLine(s, "BYE");
    dropSocket(s);
    emit invitingChanged();
}

void GameNet::onOutConnected()
{
    if (sender() != m_out) return;
    if (m_redialing)
        writeLine(m_out, QString("HELLO %1 %2 %3 %4 %5").arg(m_gameId).arg(PROTO).arg(m_session).arg(m_rxSeq).arg(m_name));
    else
        writeLine(m_out, QString("HELLO %1 %2 %3 0 %4").arg(m_gameId).arg(PROTO).arg(m_session).arg(m_name));
}

void GameNet::onOutError()
{
    QTcpSocket *s = qobject_cast<QTcpSocket *>(sender());
    if (!s || s != m_out) return;
    m_out = 0;
    dropSocket(s);
    if (m_redialing) return;          // try again on the next redial tick
    emit invitingChanged();
    emit declined("unreachable");
}

void GameNet::onNewConnection()
{
    while (m_server && m_server->hasPendingConnections()) {
        QTcpSocket *s = m_server->nextPendingConnection();
        s->setSocketOption(QAbstractSocket::LowDelayOption, 1);   // no Nagle delay for short lines
        connect(s, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
        connect(s, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    }
}

void GameNet::accept()
{
    if (!m_pending) return;
    QTcpSocket *s = m_pending;
    m_pending = 0;
    writeLine(s, "ACCEPT 0 " + m_name);
    m_peerIp = cleanIp(s->peerAddress());
    setConnected(s, m_pendingName, false);
}

void GameNet::decline()
{
    if (!m_pending) return;
    QTcpSocket *s = m_pending;
    m_pending = 0;
    writeLine(s, "DECLINE no");
    dropSocket(s);
}

void GameNet::send(const QString &text)
{
    if (!m_connected) return;
    QString t = text;
    t.replace('\n', ' ').replace('\r', ' ');
    m_outbox << t;
    if (m_link) writeLine(m_link, QString("MSG %1 %2").arg(m_outbox.size()).arg(t));
    sendUdpCopy(m_outbox.size());
    if (!m_udpResend.isActive()) m_udpResend.start();
}

void GameNet::sendUdpCopy(int seq)
{
    if (!m_udp || m_peerIp.isEmpty() || seq < 1 || seq > m_outbox.size()) return;
    QByteArray d = QString("MEEMSG %1 %2 %3 %4").arg(m_token, m_session).arg(seq).arg(m_outbox.at(seq - 1)).toUtf8();
    m_udp->writeDatagram(d, QHostAddress(m_peerIp), DISCOVERY_PORT);
}

// repeat unconfirmed lines over UDP until the other phone confirms them
void GameNet::onUdpResend()
{
    if (!m_connected || m_peerAck >= m_outbox.size()) { m_udpResend.stop(); return; }
    for (int seq = m_peerAck + 1; seq <= m_outbox.size() && seq <= m_peerAck + 8; seq++) sendUdpCopy(seq);
}

void GameNet::gotAck(int seq)
{
    if (seq > m_peerAck) m_peerAck = qMin(seq, m_outbox.size());
}

// a numbered line from the other phone (TCP or UDP copy): deliver each exactly once, in order
void GameNet::deliver(int seq, const QString &text)
{
    if (seq <= m_rxSeq) {
        // repeat: confirm again so the sender stops resending
    } else if (seq == m_rxSeq + 1) {
        m_rxSeq = seq;
        emit message(text);
        while (m_connected && m_early.contains(m_rxSeq + 1)) {
            m_rxSeq++;
            emit message(m_early.take(m_rxSeq));
        }
    } else {
        if (m_early.size() < 64) m_early.insert(seq, text);
        return;
    }
    if (!m_connected) return;
    if (m_link) writeLine(m_link, QString("ACK %1").arg(m_rxSeq));
    if (m_udp && !m_peerIp.isEmpty())
        m_udp->writeDatagram(QString("MEEACK %1 %2 %3").arg(m_token, m_session).arg(m_rxSeq).toUtf8(),
                             QHostAddress(m_peerIp), DISCOVERY_PORT);
}

void GameNet::leave()
{
    if (!m_connected) return;
    if (m_link) writeLine(m_link, "BYE");
    endMatch(QString(), false);
}

void GameNet::writeLine(QTcpSocket *s, const QString &line)
{
    s->write(line.toUtf8() + "\n");
    s->flush();
}

void GameNet::onReadyRead()
{
    QTcpSocket *s = qobject_cast<QTcpSocket *>(sender());
    if (!s) return;
    while (s->canReadLine()) {
        QString line = QString::fromUtf8(s->readLine()).trimmed();
        if (!line.isEmpty()) handleLine(s, line);
    }
}

void GameNet::handleLine(QTcpSocket *s, const QString &line)
{
    QString cmd = line.section(' ', 0, 0);
    if (s == m_link) {
        m_lastRx.restart();
        if (cmd == "MSG") deliver(line.section(' ', 1, 1).toInt(), line.section(' ', 2));
        else if (cmd == "ACK") gotAck(line.section(' ', 1, 1).toInt());
        else if (cmd == "PING") writeLine(s, "PONG");
        else if (cmd == "BYE") endMatch("bye", true);
        return;
    }
    if (s == m_out) {
        if (cmd == "ACCEPT") {
            int peerLast = line.section(' ', 1, 1).toInt();
            m_out = 0;
            if (m_redialing) {
                m_redialing = false;
                attachLink(s, peerLast);
                emit resumed();
            } else {
                m_outbox.clear();
                m_rxSeq = 0;
                setConnected(s, line.section(' ', 2).left(16), true);
                emit invitingChanged();
                emit accepted();
            }
        } else if (cmd == "DECLINE") {
            m_out = 0;
            dropSocket(s);
            if (m_redialing) { m_redialing = false; endMatch("lost", true); return; }
            emit invitingChanged();
            emit declined(line.section(' ', 1));
        }
        return;
    }
    if (s == m_pending) {
        if (cmd == "BYE") { m_pending = 0; dropSocket(s); emit inviteCancelled(); }
        return;
    }
    if (cmd == "HELLO") {
        QStringList f = line.split(' ');
        if (f.size() < 6) { dropSocket(s); return; }
        if (f[1] != m_gameId) { writeLine(s, "DECLINE game"); dropSocket(s); return; }
        if (f[2] != PROTO) { writeLine(s, "DECLINE version"); dropSocket(s); return; }
        QString session = f[3];
        int peerLast = f[4].toInt();
        if (m_connected && !m_initiator && session == m_session) {
            // the other phone reconnects to our match: take the new connection, resend what it missed
            if (m_link) { QTcpSocket *old = m_link; m_link = 0; dropSocket(old); }
            m_peerIp = cleanIp(s->peerAddress());
            writeLine(s, QString("ACCEPT %1 %2").arg(m_rxSeq).arg(m_name));
            attachLink(s, peerLast);
            emit resumed();
            return;
        }
        if (m_connected || m_pending || m_out) { writeLine(s, "DECLINE busy"); dropSocket(s); return; }
        m_pending = s;
        m_pendingName = line.section(' ', 5).left(16);
        m_session = session;
        emit invited(m_pendingName, cleanIp(s->peerAddress()));
    }
}

void GameNet::setConnected(QTcpSocket *s, const QString &peer, bool initiator)
{
    m_peerName = peer;
    m_initiator = initiator;
    m_connected = true;
    m_outbox.clear();
    m_rxSeq = 0;
    m_peerAck = 0;
    m_early.clear();
    attachLink(s, 0);
    emit connectedChanged();
}

void GameNet::attachLink(QTcpSocket *s, int peerLastSeq)
{
    m_link = s;
    s->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    gotAck(peerLastSeq);
    m_redial.stop();
    m_lastRx.start();
    m_heart.start();
    for (int i = qMax(0, peerLastSeq); i < m_outbox.size(); i++)
        writeLine(s, QString("MSG %1 %2").arg(i + 1).arg(m_outbox.at(i)));
    emit reconnectingChanged();
}

// the connection dropped during a match: keep the match, reconnect (the inviting phone dials)
void GameNet::suspend()
{
    if (!m_connected || !m_link) return;
    QTcpSocket *s = m_link;
    m_link = 0;
    dropSocket(s);
    m_heart.stop();
    m_lostAt.start();
    emit reconnectingChanged();
    emit linkLost();
    m_redial.start();
    onRedial();
}

void GameNet::onRedial()
{
    if (!m_connected || m_link) { m_redial.stop(); return; }
    if (m_lostAt.elapsed() > m_resumeSec * 1000) { endMatch("lost", true); return; }
    if (m_initiator && !m_out) {
        m_redialing = true;
        m_out = dial(m_peerIp, m_peerPort);
    }
}

void GameNet::onDisconnected()
{
    QTcpSocket *s = qobject_cast<QTcpSocket *>(sender());
    if (!s) return;
    if (s == m_link) { suspend(); return; }
    if (s == m_pending) { m_pending = 0; dropSocket(s); emit inviteCancelled(); return; }
    if (s == m_out) {
        m_out = 0;
        dropSocket(s);
        if (m_redialing) return;
        emit invitingChanged();
        emit declined("closed");
        return;
    }
    dropSocket(s);
}

void GameNet::onHeartbeat()
{
    if (!m_link) { m_heart.stop(); return; }
    if (m_lastRx.elapsed() > SILENCE_MS) { suspend(); return; }
    writeLine(m_link, "PING");
}

void GameNet::dropSocket(QTcpSocket *s)
{
    s->disconnect(this);
    s->disconnectFromHost();
    s->deleteLater();
}

void GameNet::endMatch(const QString &reason, bool notify)
{
    bool was = m_connected;
    if (m_link) { QTcpSocket *s = m_link; m_link = 0; dropSocket(s); }
    if (m_out && m_redialing) { QTcpSocket *s = m_out; m_out = 0; dropSocket(s); }
    m_redialing = false;
    m_heart.stop();
    m_redial.stop();
    m_udpResend.stop();
    m_connected = false;
    m_peerAck = 0;
    m_early.clear();
    m_session.clear();
    m_outbox.clear();
    m_rxSeq = 0;
    if (!was) return;
    emit connectedChanged();
    emit reconnectingChanged();
    if (notify) emit peerLeft(reason);
}
