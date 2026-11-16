// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors
//
// Deterministic test window for KDockW E2E tests.
//
// One process = one toplevel window. The window's Wayland app_id comes from
// --app-id (default org.kde.kdockw.testwindow, which has an installed .desktop
// file) and its title from --title, so a test can open N windows of a known
// app, find them in KWin's window list and close them again with SIGTERM.
//
// --badge N sends a Unity LauncherEntry update so badge scenarios have a
// source that is not a real notification daemon.
//
// --color C fills the window content with a solid color, so a screenshot can
// tell which window's live content a preview thumbnail shows.

#include <QApplication>
#include <QKeyEvent>
#include <QColor>
#include <QCryptographicHash>
#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QImage>
#include <QIcon>
#include <QLabel>
#include <QLocalServer>
#include <QLocalSocket>
#include <QFileInfo>
#include <QPixmap>
#include <QPalette>
#include <QMainWindow>
#include <QPushButton>
#include <QSocketNotifier>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <QWindow>

#include <csignal>
#include <cstdio>
#include <vector>
#include <sys/socket.h>
#include <unistd.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#undef KeyPress

namespace
{

void publishXcbWindowIcon(WId windowId, const QIcon &icon)
{
    if (QGuiApplication::platformName() != QLatin1String("xcb")) {
        return;
    }

    const QPixmap pixmap = icon.pixmap(QSize(64, 64));
    if (pixmap.isNull()) {
        return;
    }
    const QImage image = pixmap.toImage().convertToFormat(QImage::Format_ARGB32);
    std::vector<unsigned long> data;
    data.reserve(static_cast<size_t>(image.width() * image.height() + 2));
    data.push_back(static_cast<unsigned long>(image.width()));
    data.push_back(static_cast<unsigned long>(image.height()));
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            data.push_back(static_cast<unsigned long>(image.pixel(x, y)));
        }
    }

    static Display *display = XOpenDisplay(nullptr);
    static std::vector<Pixmap> iconPixmaps;
    if (!display) {
        return;
    }
    const auto window = static_cast<::Window>(windowId);
    const Atom netWmIcon = XInternAtom(display, "_NET_WM_ICON", False);
    XChangeProperty(display, window, netWmIcon, XA_CARDINAL, 32,
                    PropModeReplace, reinterpret_cast<const unsigned char *>(data.data()),
                    static_cast<int>(data.size()));

    const int bytesPerRow = (image.width() + 7) / 8;
    std::vector<char> bitmap(static_cast<size_t>(bytesPerRow * image.height()), 0);
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qGray(image.pixel(x, y)) > 127) {
                bitmap[static_cast<size_t>(y * bytesPerRow + x / 8)] |= static_cast<char>(1U << (x % 8));
            }
        }
    }
    const Pixmap iconPixmap = XCreateBitmapFromData(display, window, bitmap.data(), image.width(), image.height());
    if (iconPixmap != None) {
        XWMHints *hints = XGetWMHints(display, window);
        if (!hints) {
            hints = XAllocWMHints();
        }
        if (hints) {
            hints->flags |= IconPixmapHint;
            hints->icon_pixmap = iconPixmap;
            XSetWMHints(display, window, hints);
            XFree(hints);
            iconPixmaps.push_back(iconPixmap);
        } else {
            XFreePixmap(display, iconPixmap);
        }
    }
    XSync(display, False);
}

int s_sigFd[2] = {-1, -1};

void onSignal(int)
{
    const char c = 1;
    [[maybe_unused]] const auto n = ::write(s_sigFd[0], &c, 1);
}

void sendBadge(const QString &appId, int count)
{
    QDBusMessage msg = QDBusMessage::createSignal(QStringLiteral("/org/kde/kdockw/testwindow"),
                                                  QStringLiteral("com.canonical.Unity.LauncherEntry"),
                                                  QStringLiteral("Update"));
    QVariantMap props;
    props.insert(QStringLiteral("count"), qint64(count));
    props.insert(QStringLiteral("count-visible"), count > 0);
    msg << QStringLiteral("application://%1.desktop").arg(appId) << props;
    QDBusConnection::sessionBus().send(msg);
}

// Logs every key press the window receives ("key-press <title> key=0x.. mods=0x..")
// to stderr, which TestWindows sends to artifacts/test-windows.log. Lets tests
// tell "KWin swallowed the combo as a global shortcut" from "it reached the app".
class KeyLogger : public QObject
{
public:
    explicit KeyLogger(QString title)
        : m_title(std::move(title))
    {
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::KeyPress && watched->isWindowType()) {
            const auto *ke = static_cast<QKeyEvent *>(event);
            fprintf(stderr, "key-press %s key=0x%x mods=0x%x\n", qPrintable(m_title), ke->key(), uint(ke->modifiers()));
            fflush(stderr);
        }
        return false;
    }

private:
    QString m_title;
};
} // namespace

int main(int argc, char **argv)
{
    // app_id must be set before the QApplication creates its platform
    // integration, otherwise the first surface is committed with the binary
    // name as app_id.
    QString appId = QStringLiteral("org.kde.kdockw.testwindow");
    for (int i = 1; i + 1 < argc; ++i) {
        if (qstrcmp(argv[i], "--app-id") == 0) {
            appId = QString::fromLocal8Bit(argv[i + 1]);
        }
    }
    QGuiApplication::setDesktopFileName(appId);

    QApplication app(argc, argv);
    // On X11/XWayland TaskManager keys live windows by WM_CLASS, which Qt
    // derives from applicationName. Keep it aligned with --app-id so the
    // diagnostic fixture exercises its own Desktop Entry identity.
    app.setApplicationName(appId);

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({QStringLiteral("app-id"), QStringLiteral("Wayland app_id / desktop file id"), QStringLiteral("id"), appId});
    parser.addOption({QStringLiteral("title"), QStringLiteral("Window title"), QStringLiteral("title"), QStringLiteral("KDockW Test Window")});
    parser.addOption({QStringLiteral("width"), QStringLiteral("Window width"), QStringLiteral("px"), QStringLiteral("400")});
    parser.addOption({QStringLiteral("height"), QStringLiteral("Window height"), QStringLiteral("px"), QStringLiteral("300")});
    parser.addOption({QStringLiteral("badge"), QStringLiteral("Unity LauncherEntry badge count"), QStringLiteral("n"), QStringLiteral("-1")});
    parser.addOption({QStringLiteral("color"), QStringLiteral("Solid background color of the window content (e.g. red, #00ff00)"), QStringLiteral("color")});
    parser.addOption({QStringLiteral("icon-path"), QStringLiteral("Explicit local test icon path"), QStringLiteral("path")});
    parser.addOption({QStringLiteral("control-socket"), QStringLiteral("Private QLocalServer path for an automated test controller"), QStringLiteral("path")});
    parser.process(app);

    ::socketpair(AF_UNIX, SOCK_STREAM, 0, s_sigFd);
    QSocketNotifier sigNotifier(s_sigFd[1], QSocketNotifier::Read);
    QObject::connect(&sigNotifier, &QSocketNotifier::activated, &app, &QCoreApplication::quit);
    struct sigaction sa = {};
    sa.sa_handler = onSignal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGTERM, &sa, nullptr);
    sigaction(SIGINT, &sa, nullptr);

    const QString title = parser.value(QStringLiteral("title"));
    KeyLogger keyLogger(title);
    app.installEventFilter(&keyLogger);

    QMainWindow window;
    window.setWindowTitle(title);
    auto *central = new QWidget(&window);
    if (const QColor color(parser.value(QStringLiteral("color"))); color.isValid()) {
        QPalette pal = central->palette();
        pal.setColor(QPalette::Window, color);
        central->setPalette(pal);
        central->setAutoFillBackground(true);
    }
    auto *layout = new QVBoxLayout(central);
    auto *label = new QLabel(title, central);
    label->setObjectName(QStringLiteral("titleLabel"));
    layout->addWidget(label);
    auto *quit = new QPushButton(QStringLiteral("Quit"), central);
    QObject::connect(quit, &QPushButton::clicked, &app, &QCoreApplication::quit);
    layout->addWidget(quit);
    window.setCentralWidget(central);
    window.resize(parser.value(QStringLiteral("width")).toInt(), parser.value(QStringLiteral("height")).toInt());
    if (QGuiApplication::platformName() == QLatin1String("xcb")) {
        // Qt's XCB WM_CLASS otherwise remains the test executable's name,
        // which prevents KWin/TaskManager from matching the per-run Desktop
        // Entry used by the live diagnostic fixture.
        if (Display *display = XOpenDisplay(nullptr)) {
            QByteArray className = appId.toLocal8Bit();
            XClassHint classHint{className.data(), className.data()};
            XSetClassHint(display, static_cast<::Window>(window.winId()), &classHint);
            XFlush(display);
            XCloseDisplay(display);
        }
    }
    if (const QString iconPath = parser.value(QStringLiteral("icon-path")); !iconPath.isEmpty()) {
        // This is a raw-render test stimulus, not a claim about Wayland app_id semantics.
        window.setWindowIcon(QIcon(iconPath));
        publishXcbWindowIcon(window.winId(), window.windowIcon());
    }

    QLocalServer controlServer;
    if (const QString socketPath = parser.value(QStringLiteral("control-socket")); !socketPath.isEmpty()) {
        if (QFileInfo::exists(socketPath) || !controlServer.listen(socketPath)) {
            qCritical("Could not bind the requested private test control socket");
            return 3;
        }
        QObject::connect(&controlServer, &QLocalServer::newConnection, &app, [&] {
            while (auto *socket = controlServer.nextPendingConnection()) {
                auto *buffer = new QByteArray;
                QObject::connect(socket, &QLocalSocket::readyRead, &app, [socket, buffer, &window, &app] {
                    buffer->append(socket->readAll());
                    const auto newline = buffer->indexOf('\n');
                    if (newline < 0) {
                        return;
                    }
                    const auto request = QJsonDocument::fromJson(buffer->left(newline)).object();
                    const QString operation = request.value(QStringLiteral("operation")).toString();
                    bool ok = true;
                    if (operation == QLatin1String("setTitle")) {
                        window.setWindowTitle(request.value(QStringLiteral("value")).toString());
                    } else if (operation == QLatin1String("setIcon")) {
                        const QIcon icon(request.value(QStringLiteral("value")).toString());
                        ok = !icon.isNull();
                        if (ok) {
                            window.setWindowIcon(icon);
                            publishXcbWindowIcon(window.winId(), window.windowIcon());
                        }
                    } else if (operation == QLatin1String("minimize")) {
                        window.showMinimized();
                    } else if (operation == QLatin1String("restore")) {
                        window.showNormal();
                    } else if (operation == QLatin1String("activate")) {
                        window.showNormal();
                        window.raise();
                        window.activateWindow();
                        if (window.windowHandle()) {
                            window.windowHandle()->requestActivate();
                        }
                    } else if (operation == QLatin1String("close")) {
                        window.close();
                        QTimer::singleShot(0, &app, &QCoreApplication::quit);
                    } else if (operation != QLatin1String("ping")) {
                        ok = false;
                    }

                    const QPixmap pixmap = window.windowIcon().pixmap(QSize(64, 64));
                    const QImage image = pixmap.toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);
                    QByteArray pixels;
                    if (!image.isNull()) {
                        pixels = QByteArray(reinterpret_cast<const char *>(image.constBits()),
                                             static_cast<qsizetype>(image.sizeInBytes()));
                    }
                    const QJsonObject response{
                        {QStringLiteral("ok"), ok},
                        {QStringLiteral("title"), window.windowTitle()},
                        {QStringLiteral("iconCacheKey"), QString::number(window.windowIcon().cacheKey())},
                        {QStringLiteral("iconPixelSha256"), QString::fromLatin1(QCryptographicHash::hash(pixels, QCryptographicHash::Sha256).toHex())},
                        {QStringLiteral("minimized"), window.isMinimized()},
                        {QStringLiteral("visible"), window.isVisible()},
                    };
                    socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
                    socket->flush();
                    socket->disconnectFromServer();
                });
                QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
                QObject::connect(socket, &QObject::destroyed, &app, [buffer] { delete buffer; });
            }
        });
    }
    window.show();

    if (const int badge = parser.value(QStringLiteral("badge")).toInt(); badge >= 0) {
        sendBadge(appId, badge);
    }

    return app.exec();
}
