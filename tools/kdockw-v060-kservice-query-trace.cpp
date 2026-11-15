// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include <KApplicationTrader>
#include <KService>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>
#include <fcntl.h>
#include <string>
#include <thread>
#include <unistd.h>

namespace
{
std::atomic<unsigned long long> queryCount{0};
std::atomic<bool> stopWriter{false};
std::thread writer;
int outputFd = -1;

using QueryFunction = KService::List (*)(KApplicationTrader::FilterFunc);

QueryFunction originalQuery()
{
    static auto *function = reinterpret_cast<QueryFunction>(dlsym(RTLD_NEXT,
        "_ZN18KApplicationTrader5queryESt8functionIFbRK28QExplicitlySharedDataPointerI8KServiceEEE"));
    return function;
}

void writeCounts()
{
    using Clock = std::chrono::steady_clock;
    auto previous = Clock::now();
    while (!stopWriter.load(std::memory_order_relaxed)) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        const auto now = Clock::now();
        const auto elapsedNs = std::chrono::duration_cast<std::chrono::nanoseconds>(now - previous).count();
        previous = now;
        const auto count = queryCount.exchange(0, std::memory_order_relaxed);
        if (outputFd >= 0) {
            char line[96];
            const int length = std::snprintf(line, sizeof(line), "%lld,%llu,0\n",
                static_cast<long long>(elapsedNs), count);
            if (length > 0) {
                const ssize_t ignored = write(outputFd, line, static_cast<size_t>(length));
                (void)ignored;
            }
        }
    }
}
}

extern "C" KService::List kdockwTraceKApplicationTraderQuery(KApplicationTrader::FilterFunc filter)
    __asm__("_ZN18KApplicationTrader5queryESt8functionIFbRK28QExplicitlySharedDataPointerI8KServiceEEE");

extern "C" KService::List kdockwTraceKApplicationTraderQuery(KApplicationTrader::FilterFunc filter)
{
    queryCount.fetch_add(1, std::memory_order_relaxed);
    const auto function = originalQuery();
    if (!function) {
        return {};
    }
    return function(std::move(filter));
}

__attribute__((constructor)) static void startTraceWriter()
{
    const char *path = std::getenv("KDOCKW_KSERVICE_TRACE_OUT");
    if (!path || !*path) {
        return;
    }
    outputFd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    writer = std::thread(writeCounts);
}

__attribute__((destructor)) static void stopTraceWriter()
{
    stopWriter.store(true, std::memory_order_relaxed);
    if (writer.joinable()) {
        writer.join();
    }
    if (outputFd >= 0) {
        const auto count = queryCount.exchange(0, std::memory_order_relaxed);
        if (count > 0) {
            char line[96];
            const int length = std::snprintf(line, sizeof(line), "0,%llu,1\n", count);
            if (length > 0) {
                const ssize_t ignored = write(outputFd, line, static_cast<size_t>(length));
                (void)ignored;
            }
        }
        close(outputFd);
    }
}
