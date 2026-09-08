// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2022 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <mutex>
#include <utility>
#include <type_traits>

#include <boost/asio.hpp>
#include <boost/version.hpp>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE
// Boost::process isn't built for iOS (libs/process/src/shell.cpp calls
// wordexp()/wordfree(), unavailable in the iOS sandbox; see the IOS branch
// in the top-level CMakeLists.txt). signal_pipe below only needs a
// same-process wakeup channel, so use a plain OS pipe wrapped in
// boost::asio::posix::stream_descriptor instead of boost::process::async_pipe.
#define AETHEREMU_ASIO_SIGNAL_PIPE 1
#include <boost/asio/posix/stream_descriptor.hpp>
#include <stdexcept>
#include <unistd.h>
#else
#define AETHEREMU_ASIO_SIGNAL_PIPE 0
#if BOOST_VERSION > 108400 && (!defined(_WINDOWS) && !defined(__ANDROID__)) || defined(YUZU_BOOST_v1)
#define USE_BOOST_v1
#endif
#ifdef USE_BOOST_v1
#include <boost/process/v1/async_pipe.hpp>
#else
#include <boost/process/async_pipe.hpp>
#endif
#endif

#include "common/logging.h"
#include "common/polyfill_thread.h"
#include "common/thread.h"
#include "core/core.h"
#include "core/debugger/debugger.h"
#include "core/debugger/debugger_interface.h"
#include "core/debugger/gdbstub.h"
#include "core/hle/kernel/global_scheduler_context.h"
#include "core/hle/kernel/k_process.h"
#include "core/hle/kernel/k_scheduler.h"

template <typename Readable, typename Buffer, typename Callback>
static void AsyncReceiveInto(Readable& r, Buffer& buffer, Callback&& c) {
    static_assert(std::is_trivial_v<Buffer>);
    auto boost_buffer{boost::asio::buffer(&buffer, sizeof(Buffer))};
    r.async_read_some(
        boost_buffer, [&, c](const boost::system::error_code& error, size_t bytes_read) {
            if (!error.failed()) {
                const u8* buffer_start = reinterpret_cast<const u8*>(&buffer);
                std::span<const u8> received_data{buffer_start, buffer_start + bytes_read};
                c(received_data);
                AsyncReceiveInto(r, buffer, c);
            }
        });
}

template <typename Callback>
static void AsyncAccept(boost::asio::ip::tcp::acceptor& acceptor, Callback&& c) {
    acceptor.async_accept([&, c](const boost::system::error_code& error, auto&& peer_socket) {
        if (!error.failed()) {
            c(peer_socket);
            AsyncAccept(acceptor, c);
        }
    });
}

template <typename Readable, typename Buffer>
static std::span<const u8> ReceiveInto(Readable& r, Buffer& buffer) {
    static_assert(std::is_trivial_v<Buffer>);
    auto boost_buffer{boost::asio::buffer(&buffer, sizeof(Buffer))};
    size_t bytes_read = r.read_some(boost_buffer);
    const u8* buffer_start = reinterpret_cast<const u8*>(&buffer);
    std::span<const u8> received_data{buffer_start, buffer_start + bytes_read};
    return received_data;
}

enum class SignalType {
    Stopped,
    Watchpoint,
    ShuttingDown,
};

struct SignalInfo {
    SignalType type;
    Kernel::KThread* thread;
    const Kernel::DebugWatchpoint* watchpoint;
};

namespace Core {

class DebuggerImpl : public DebuggerBackend {
public:
    explicit DebuggerImpl(Core::System& system_, u16 port)
        : system{system_}
        , debug_process{system_.Kernel()}
    {
        InitializeServer(port);
    }

    ~DebuggerImpl() override {
        ShutdownServer();
    }

    bool SignalDebugger(SignalInfo signal_info) {
        std::scoped_lock lk{connection_lock};

        if (stopped || !state) {
            // Do not notify the debugger about another event.
            // It should be ignored.
            return false;
        }

        // Set up the state.
        stopped = true;
        state->info = signal_info;

        // Write a single byte into the pipe to wake up the debug interface.
        boost::asio::write(state->signal_pipe, boost::asio::buffer(&stopped, sizeof(stopped)));

        return true;
    }

    // These functions are callbacks from the frontend, and the lock will be held.
    // There is no need to relock it.

    std::span<const u8> ReadFromClient() override {
        return ReceiveInto(state->client_socket, state->client_data);
    }

    void WriteToClient(std::span<const u8> data) override {
        boost::asio::write(state->client_socket,
                           boost::asio::buffer(data.data(), data.size_bytes()));
    }

    void SetActiveThread(Kernel::KThread* thread) override {
        state->active_thread = {system.Kernel(), thread};
    }

    Kernel::KThread* GetActiveThread() override {
        return state->active_thread.GetPointerUnsafe();
    }

private:
    void InitializeServer(u16 port) {
        using boost::asio::ip::tcp;

        LOG_INFO(Debug_GDBStub, "Starting server on port {}...", port);

        // Run the connection thread.
        connection_thread = std::jthread([&, port](std::stop_token stop_token) {
            Common::SetCurrentThreadName("Debugger");

            try {
                // Initialize the listening socket and accept a new client.
                tcp::endpoint endpoint{boost::asio::ip::address_v4::any(), port};
                tcp::acceptor acceptor{io_context, endpoint};

                AsyncAccept(acceptor, [&](auto&& peer) { AcceptConnection(std::move(peer)); });

                while (!stop_token.stop_requested() && io_context.run()) {
                }
            } catch (const std::exception& ex) {
                LOG_CRITICAL(Debug_GDBStub, "Stopping server: {}", ex.what());
            }
        });
    }

    void AcceptConnection(boost::asio::ip::tcp::socket&& peer) {
        LOG_INFO(Debug_GDBStub, "Accepting new peer connection");

        std::scoped_lock lk{connection_lock};

        // Find the process we are going to debug.
        SetDebugProcess();

        // Ensure everything is stopped.
        PauseEmulation();

        // Set up the new frontend.
        frontend = std::make_unique<GDBStub>(*this, system, debug_process.GetPointerUnsafe());

        // Set the new state. This will tear down any existing state.
        state.emplace(std::move(peer), io_context, system.Kernel());

        // Set up the client signals for new data.
        AsyncReceiveInto(state->signal_pipe, state->pipe_data, [&](auto d) { PipeData(d); });
        AsyncReceiveInto(state->client_socket, state->client_data, [&](auto d) { ClientData(d); });

        // Set the active thread.
        UpdateActiveThread();

        // Set up the frontend.
        frontend->Connected();
    }

    void ShutdownServer() {
        connection_thread.request_stop();
        io_context.stop();
        connection_thread.join();
    }

    void PipeData(std::span<const u8> data) {
        std::scoped_lock lk{connection_lock};

        switch (state->info.type) {
        case SignalType::Stopped:
        case SignalType::Watchpoint:
            // Stop emulation.
            PauseEmulation();

            // Notify the client.
            state->active_thread = {system.Kernel(), state->info.thread};
            UpdateActiveThread();

            if (state->info.type == SignalType::Watchpoint) {
                frontend->Watchpoint(std::addressof(*state->active_thread),
                                     *state->info.watchpoint);
            } else {
                frontend->Stopped(std::addressof(*state->active_thread));
            }

            break;
        case SignalType::ShuttingDown:
            frontend->ShuttingDown();

            // Release members.
            state->active_thread.Reset(nullptr);
            debug_process.Reset(nullptr);

            // Wait for emulation to shut down gracefully now.
            state->signal_pipe.close();
            state->client_socket.shutdown(boost::asio::socket_base::shutdown_both);
            LOG_INFO(Debug_GDBStub, "Shut down server");

            break;
        }
    }

    void ClientData(std::span<const u8> data) {
        std::scoped_lock lk{connection_lock};

        const auto actions{frontend->ClientData(data)};
        for (const auto action : actions) {
            switch (action) {
            case DebuggerAction::Interrupt: {
                stopped = true;
                PauseEmulation();
                UpdateActiveThread();
                frontend->Stopped(state->active_thread.GetPointerUnsafe());
                break;
            }
            case DebuggerAction::Continue:
                MarkResumed([&] { ResumeEmulation(); });
                break;
            case DebuggerAction::ContinueThreads: {
                auto* gdb = static_cast<GDBStub*>(frontend.get());
                MarkResumed([this, threads = std::move(gdb->resume_threads)] {
                    ResumeThreads(threads);
                });
                break;
            }
            case DebuggerAction::StepThread: {
                auto* gdb = static_cast<GDBStub*>(frontend.get());
                MarkResumed([this, threads = std::move(gdb->resume_threads)] {
                    state->active_thread->SetStepState(Kernel::StepState::StepPending);
                    state->active_thread->Resume(system.Kernel(), Kernel::SuspendType::Debug);
                    ResumeThreads(threads, state->active_thread.GetPointerUnsafe());
                });
                break;
            }
            case DebuggerAction::ShutdownEmulation: {
                // Spawn another thread that will exit after shutdown,
                // to avoid a deadlock
                Core::System* system_ref{&system};
                std::thread t([system_ref] { system_ref->Exit(); });
                t.detach();
                break;
            }
            }
        }
    }

    void PauseEmulation() {
        Kernel::KScopedLightLock ll{debug_process->GetListLock()};
        Kernel::KScopedSchedulerLock sl{system.Kernel()};

        // Put all threads to sleep on next scheduler round.
        for (auto& thread : ThreadList()) {
            thread.RequestSuspend(system.Kernel(), Kernel::SuspendType::Debug);
        }
    }

    void ResumeEmulation(Kernel::KThread* except = nullptr) {
        Kernel::KScopedLightLock ll{debug_process->GetListLock()};
        Kernel::KScopedSchedulerLock sl{system.Kernel()};

        // Wake up all threads.
        for (auto& thread : ThreadList()) {
            if (std::addressof(thread) == except) {
                continue;
            }

            thread.SetStepState(Kernel::StepState::NotStepping);
            thread.Resume(system.Kernel(), Kernel::SuspendType::Debug);
        }
    }

    void ResumeThreads(const std::vector<Kernel::KThread*>& threads,
                       Kernel::KThread* except = nullptr) {
        Kernel::KScopedLightLock ll{debug_process->GetListLock()};
        Kernel::KScopedSchedulerLock sl{system.Kernel()};

        // Wake up only the specified threads.
        for (auto* thread : threads) {
            if (!thread || thread == except) {
                continue;
            }

            thread->SetStepState(Kernel::StepState::NotStepping);
            thread->Resume(system.Kernel(), Kernel::SuspendType::Debug);
        }
    }

    template <typename Callback>
    void MarkResumed(Callback&& cb) {
        stopped = false;
        cb();
    }

    void UpdateActiveThread() {
        Kernel::KScopedLightLock ll{debug_process->GetListLock()};

        auto& threads{ThreadList()};
        for (auto& thread : threads) {
            if (std::addressof(thread) == state->active_thread.GetPointerUnsafe()) {
                // Thread is still alive, no need to update.
                return;
            }
        }
        state->active_thread = {system.Kernel(), std::addressof(threads.front())};
    }

private:
    void SetDebugProcess() {
        debug_process = std::move(system.Kernel().GetProcessList().back());
    }

    Kernel::KProcess::ThreadList& ThreadList() {
        return debug_process->GetThreadList();
    }

private:
    System& system;
    Kernel::KScopedAutoObject<Kernel::KProcess> debug_process;
    std::unique_ptr<DebuggerFrontend> frontend;

    boost::asio::io_context io_context;
    std::jthread connection_thread;
    std::mutex connection_lock;

    struct ConnectionState {
#if AETHEREMU_ASIO_SIGNAL_PIPE
        // Minimal stand-in for boost::process::async_pipe's read/write surface,
        // backed by a real pipe(2) so no boost::process dependency is needed.
        class SignalPipe {
        public:
            // Intentionally implicit: ConnectionState's constructor takes this
            // by value and callers pass `io_context` directly, same as the
            // boost::process::async_pipe(io_context&) constructor it replaces.
            SignalPipe(boost::asio::io_context& io_context) {
                int fds[2];
                if (::pipe(fds) != 0) {
                    throw std::runtime_error("SignalPipe: failed to create pipe");
                }
                read_end.emplace(io_context, fds[0]);
                write_end.emplace(io_context, fds[1]);
            }

            template <typename MutableBufferSequence, typename Handler>
            void async_read_some(const MutableBufferSequence& buffers, Handler&& handler) {
                read_end->async_read_some(buffers, std::forward<Handler>(handler));
            }

            template <typename ConstBufferSequence>
            size_t write_some(const ConstBufferSequence& buffers) {
                return write_end->write_some(buffers);
            }

            void close() {
                boost::system::error_code ec;
                if (read_end) {
                    read_end->close(ec);
                }
                if (write_end) {
                    write_end->close(ec);
                }
            }

        private:
            std::optional<boost::asio::posix::stream_descriptor> read_end;
            std::optional<boost::asio::posix::stream_descriptor> write_end;
        };
        using async_pipe = SignalPipe;
#elif defined(USE_BOOST_v1)
        using async_pipe = boost::process::v1::async_pipe;
#else
        using async_pipe = boost::process::async_pipe;
#endif

        ConnectionState(boost::asio::ip::tcp::socket&& client_socket_, async_pipe signal_pipe_, Kernel::KernelCore& kernel)
            : client_socket{std::move(client_socket_)}
            , signal_pipe{std::move(signal_pipe_)}
            , active_thread{kernel, nullptr}
        {}

        boost::asio::ip::tcp::socket client_socket;
        async_pipe signal_pipe;
        SignalInfo info;
        Kernel::KScopedAutoObject<Kernel::KThread> active_thread;
        std::array<u8, 4096> client_data;
        bool pipe_data;
    };

    std::optional<ConnectionState> state{};
    bool stopped{};
};

Debugger::Debugger(Core::System& system, u16 port) {
    try {
        impl = std::make_unique<DebuggerImpl>(system, port);
    } catch (const std::exception& ex) {
        LOG_CRITICAL(Debug_GDBStub, "Failed to initialize debugger: {}", ex.what());
    }
}

Debugger::~Debugger() = default;

bool Debugger::NotifyThreadStopped(Kernel::KThread* thread) {
    return impl && impl->SignalDebugger(SignalInfo{SignalType::Stopped, thread, nullptr});
}

bool Debugger::NotifyThreadWatchpoint(Kernel::KThread* thread,
                                      const Kernel::DebugWatchpoint& watch) {
    return impl && impl->SignalDebugger(SignalInfo{SignalType::Watchpoint, thread, &watch});
}

void Debugger::NotifyShutdown() {
    if (impl) {
        impl->SignalDebugger(SignalInfo{SignalType::ShuttingDown, nullptr, nullptr});
    }
}

} // namespace Core
