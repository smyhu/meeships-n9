/* GameNet - shared 1v1 Wi-Fi link for the N9 MeeGames (games-common). See gamenet.h.
 * Copyright (c) 2026 smyhu. MIT License (see LICENSE). */
#include "gamenet.h"
#include <QtCore/QStringList>
#include <QtCore/QDateTime>
#include <QtNetwork/QNetworkInterface>
#include <QtNetwork/QHostAddress>

static const quint16 DISCOVERY_PORT = 45454;
static const quint16 FIRST_TCP_PORT = 45455;
static const char *PROTO = "1";

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

GameNet::GameNet(QObject *parent)
    : QObject(parent), m_gameId("game"), m_name("N9"), m_active(false), m_connected(false),
      m_initiator(false), m_port(0), m_server(0), m_udp(0), m_link(0), m_out(0), m_pending(0)
{
    qsrand(QDateTime::currentDateTime().toTime_t() ^ (quintptr)this);
    m_token = QString::number(qrand() % 900000 + 100000);
    m_beacon.setInterval(1500);
    m_heart.setInterval(2000);
    connect(&m_beacon, SIGNAL(timeout()), this, SLOT(onBeacon()));
    connect(&m_heart, SIGNAL(timeout()), this, SLOT(onHeartbeat()));
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
        QByteArray d = QString("MEEGAMES 1 %1 %2 %3 %4 %5").arg(m_gameId).arg(m_port)
                .arg((m_link || m_pending || m_out) ? 1 : 0).arg(m_token).arg(m_name).toUtf8();
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
        if (f.size() < 7 || f[0] != "MEEGAMES" || f[1] != "1") continue;
        if (f[2] != m_gameId || f[5] == m_token) continue;
        Peer p;
        p.ip = from.toString();
        if (p.ip.startsWith("::ffff:")) p.ip = p.ip.mid(7);
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
void GameNet::invite(const QString &ip, int port)
{
    if (m_link || m_out) return;
    m_out = new QTcpSocket(this);
    connect(m_out, SIGNAL(connected()), this, SLOT(onOutConnected()));
    connect(m_out, SIGNAL(error(QAbstractSocket::SocketError)), this, SLOT(onOutError()));
    connect(m_out, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(m_out, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    m_out->connectToHost(ip.trimmed(), quint16(port > 0 ? port : FIRST_TCP_PORT));
    emit invitingChanged();
}

void GameNet::cancelInvite()
{
    if (!m_out) return;
    QTcpSocket *s = m_out;
    m_out = 0;
    if (s->state() == QAbstractSocket::ConnectedState) writeLine(s, "BYE");
    dropSocket(s);
    emit invitingChanged();
}

void GameNet::onOutConnected()
{
    if (sender() == m_out)
        writeLine(m_out, QString("HELLO %1 %2 %3").arg(m_gameId).arg(PROTO).arg(m_name));
}

void GameNet::onOutError()
{
    QTcpSocket *s = qobject_cast<QTcpSocket *>(sender());
    if (!s || s != m_out) return;
    m_out = 0;
    dropSocket(s);
    emit invitingChanged();
    emit declined("unreachable");
}

void GameNet::onNewConnection()
{
    while (m_server && m_server->hasPendingConnections()) {
        QTcpSocket *s = m_server->nextPendingConnection();
        connect(s, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
        connect(s, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    }
}

void GameNet::accept()
{
    if (!m_pending) return;
    QTcpSocket *s = m_pending;
    m_pending = 0;
    writeLine(s, "ACCEPT " + m_name);
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
    if (!m_link) return;
    QString t = text;
    t.replace('\n', ' ').replace('\r', ' ');
    writeLine(m_link, "MSG " + t);
}

void GameNet::leave()
{
    if (!m_link) return;
    writeLine(m_link, "BYE");
    closeMatch(QString(), false);
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
    QString rest = line.section(' ', 1);
    if (s == m_link) {
        m_lastRx.restart();
        if (cmd == "MSG") emit message(rest);
        else if (cmd == "PING") writeLine(s, "PONG");
        else if (cmd == "BYE") closeMatch("bye", true);
        return;
    }
    if (s == m_out) {
        if (cmd == "ACCEPT") {
            m_out = 0;
            setConnected(s, rest.left(16), true);
            emit invitingChanged();
            emit accepted();
        } else if (cmd == "DECLINE") {
            m_out = 0;
            dropSocket(s);
            emit invitingChanged();
            emit declined(rest);
        }
        return;
    }
    if (s == m_pending) {
        if (cmd == "BYE") { m_pending = 0; dropSocket(s); emit inviteCancelled(); }
        return;
    }
    if (cmd == "HELLO") {
        QStringList f = line.split(' ');
        if (f.size() < 4) { dropSocket(s); return; }
        if (f[1] != m_gameId) { writeLine(s, "DECLINE game"); dropSocket(s); return; }
        if (f[2] != PROTO) { writeLine(s, "DECLINE version"); dropSocket(s); return; }
        if (m_link || m_pending || m_out) { writeLine(s, "DECLINE busy"); dropSocket(s); return; }
        m_pending = s;
        m_pendingName = line.section(' ', 3).left(16);
        QString ip = s->peerAddress().toString();
        if (ip.startsWith("::ffff:")) ip = ip.mid(7);
        emit invited(m_pendingName, ip);
    }
}

void GameNet::setConnected(QTcpSocket *s, const QString &peer, bool initiator)
{
    m_link = s;
    m_peerName = peer;
    m_initiator = initiator;
    m_connected = true;
    m_lastRx.start();
    m_heart.start();
    emit connectedChanged();
}

void GameNet::onDisconnected()
{
    QTcpSocket *s = qobject_cast<QTcpSocket *>(sender());
    if (!s) return;
    if (s == m_link) { closeMatch("lost", true); return; }
    if (s == m_pending) { m_pending = 0; dropSocket(s); emit inviteCancelled(); return; }
    if (s == m_out) { m_out = 0; dropSocket(s); emit invitingChanged(); emit declined("closed"); return; }
    dropSocket(s);
}

void GameNet::onHeartbeat()
{
    if (!m_link) { m_heart.stop(); return; }
    if (m_lastRx.elapsed() > 8000) { closeMatch("lost", true); return; }
    writeLine(m_link, "PING");
}

void GameNet::dropSocket(QTcpSocket *s)
{
    s->disconnect(this);
    s->disconnectFromHost();
    s->deleteLater();
}

void GameNet::closeMatch(const QString &reason, bool notify)
{
    if (!m_link) return;
    QTcpSocket *s = m_link;
    m_link = 0;
    m_heart.stop();
    dropSocket(s);
    m_connected = false;
    emit connectedChanged();
    if (notify) emit peerLeft(reason);
}
