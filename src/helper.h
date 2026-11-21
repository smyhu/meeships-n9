/* Settings, language and screen helpers for QML.
 * Copyright (c) 2026 smyhu. MIT License (see LICENSE). */
#ifndef APP_HELPER_H
#define APP_HELPER_H
#include <QtCore/QObject>
#include <QtCore/QVariant>
#include <QtCore/QSettings>
#include <QtSystemInfo/QSystemScreenSaver>
QTM_USE_NAMESPACE

class Helper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString language READ language CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
public:
    Helper(QSettings *settings, QObject *parent = 0);
    Q_INVOKABLE QVariant setting(const QString &key, const QVariant &def);
    Q_INVOKABLE void setSetting(const QString &key, const QVariant &value);
    Q_INVOKABLE void keepScreenOn(bool on);
    QString language() const;
    QString version() const { return QString(APP_VERSION); }
private:
    QSettings *m_settings;
    QSystemScreenSaver *m_saver;
};
#endif
