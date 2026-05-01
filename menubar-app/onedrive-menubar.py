#!/usr/bin/env python3
"""
OneDrive Sync — macOS menu bar companion app

Requires: python3 (built-in on macOS 10.15+), rumps (vendored via setup.sh)
"""
import sys
import os
import re
import subprocess
import threading

# Vendored deps (installed by setup.sh)
_vendor = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vendor')
if os.path.isdir(_vendor):
    sys.path.insert(0, _vendor)

import rumps  # noqa: E402

SCRIPT_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYNC_SCRIPT = os.path.join(SCRIPT_DIR, 'onedrive-sync.sh')
LOG_FILE    = os.path.join(SCRIPT_DIR, 'rclone.log')
LAST_RUN    = os.path.join(SCRIPT_DIR, 'last-run.conf')

_ANSI_RE = re.compile(r'\x1b\[[0-9;]*[mABCDEFGHJKSTfnrhl]|\x1b\[?[0-9;]*[a-zA-Z]')


def strip_ansi(s: str) -> str:
    return _ANSI_RE.sub('', s)


def read_last_run() -> dict:
    cfg = {}
    try:
        with open(LAST_RUN) as f:
            for line in f:
                k, _, v = line.strip().partition('=')
                cfg[k.strip()] = v.strip().strip('"')
    except FileNotFoundError:
        pass
    return cfg


def run_on_main(fn):
    """Schedule fn() to run on the AppKit main thread."""
    import AppKit
    AppKit.NSOperationQueue.mainQueue().addOperationWithBlock_(fn)


# ── Progress window ────────────────────────────────────────────────────────────

class ProgressWindow:
    """Dark terminal-style NSWindow that shows sync output lines."""

    def __init__(self):
        import AppKit
        self._AppKit = AppKit

        rect = AppKit.NSMakeRect(200, 200, 740, 480)
        style = (
            AppKit.NSWindowStyleMaskTitled
            | AppKit.NSWindowStyleMaskClosable
            | AppKit.NSWindowStyleMaskResizable
            | AppKit.NSWindowStyleMaskMiniaturizable
        )
        self.win = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            rect, style, AppKit.NSBackingStoreBuffered, False
        )
        self.win.setTitle_('OneDrive Sync — Progress')
        self.win.setLevel_(AppKit.NSFloatingWindowLevel)

        scroll = AppKit.NSScrollView.alloc().initWithFrame_(
            AppKit.NSMakeRect(0, 0, 740, 480)
        )
        scroll.setHasVerticalScroller_(True)
        scroll.setAutohidesScrollers_(True)
        scroll.setAutoresizingMask_(
            AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable
        )

        self.tv = AppKit.NSTextView.alloc().initWithFrame_(
            AppKit.NSMakeRect(0, 0, 740, 480)
        )
        self.tv.setEditable_(False)
        self.tv.setSelectable_(True)
        self.tv.setFont_(AppKit.NSFont.fontWithName_size_('Menlo', 11))
        self.tv.setBackgroundColor_(
            AppKit.NSColor.colorWithRed_green_blue_alpha_(0.06, 0.06, 0.08, 1.0)
        )
        self.tv.setTextColor_(
            AppKit.NSColor.colorWithRed_green_blue_alpha_(0.78, 0.95, 0.78, 1.0)
        )
        self.tv.setAutoresizingMask_(
            AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable
        )
        self.tv.setTextContainerInset_(AppKit.NSMakeSize(6, 6))

        scroll.setDocumentView_(self.tv)
        self.win.setContentView_(scroll)

        self._font  = AppKit.NSFont.fontWithName_size_('Menlo', 11)
        self._color = AppKit.NSColor.colorWithRed_green_blue_alpha_(0.78, 0.95, 0.78, 1.0)
        self._err_color = AppKit.NSColor.colorWithRed_green_blue_alpha_(1.0, 0.45, 0.45, 1.0)
        self._dim_color = AppKit.NSColor.colorWithRed_green_blue_alpha_(0.5, 0.5, 0.55, 1.0)

    def show(self):
        self.win.makeKeyAndOrderFront_(None)
        self._AppKit.NSApp.activateIgnoringOtherApps_(True)

    def clear(self):
        run_on_main(lambda: self.tv.setString_(''))

    def append(self, text: str, style: str = 'normal'):
        if style == 'error':
            color = self._err_color
        elif style == 'dim':
            color = self._dim_color
        else:
            color = self._color

        attrs = {
            self._AppKit.NSFontAttributeName:            self._font,
            self._AppKit.NSForegroundColorAttributeName: color,
        }
        astr = (
            self._AppKit.NSAttributedString
            .alloc()
            .initWithString_attributes_(text + '\n', attrs)
        )

        def _do():
            s = self.tv.textStorage()
            s.appendAttributedString_(astr)
            self.tv.scrollRangeToVisible_(
                self._AppKit.NSMakeRange(s.length(), 0)
            )

        run_on_main(_do)


# ── Main app ───────────────────────────────────────────────────────────────────

class OneDriveSyncApp(rumps.App):

    def __init__(self):
        super().__init__('☁', quit_button=None)
        self._proc        = None
        self._progress_win = None

        self.menu = [
            rumps.MenuItem('▶  Start  (last settings)', callback=self.start_last),
            rumps.MenuItem('⚙  Configure in Terminal',  callback=self.open_terminal),
            None,
            rumps.MenuItem('📋  Show Progress',          callback=self.show_progress),
            rumps.MenuItem('📄  Open Log',               callback=self.open_log),
            None,
            rumps.MenuItem('⏹  Stop Sync',              callback=None),
            None,
            rumps.MenuItem('Quit', callback=lambda _: rumps.quit_application()),
        ]

    # ── Menu actions ──────────────────────────────────────────────────────────

    def start_last(self, _):
        if self._proc and self._proc.poll() is None:
            rumps.alert('A sync is already running.')
            return

        cfg = read_last_run()
        if not cfg:
            rumps.alert(
                'No previous settings found.\n\n'
                'Run the script in Terminal first to create last-run.conf.'
            )
            return

        dest = cfg.get('DEST', '')
        if dest and not os.path.isdir(dest):
            rumps.alert(
                f'Destination drive not found:\n{dest}\n\n'
                'Plug in the drive or reconfigure via Terminal.'
            )
            return

        self._run_sync()

    def open_terminal(self, _):
        osa = (
            f'tell application "Terminal"\n'
            f'  activate\n'
            f'  do script "bash \\"{SYNC_SCRIPT}\\""\n'
            f'end tell'
        )
        subprocess.run(['osascript', '-e', osa])

    def show_progress(self, _):
        self._ensure_progress_win()
        self._progress_win.show()

    def open_log(self, _):
        if os.path.exists(LOG_FILE):
            subprocess.run(['open', '-a', 'Console', LOG_FILE])
        else:
            rumps.alert('No log file found yet.\nRun a sync first.')

    # ── Sync runner ───────────────────────────────────────────────────────────

    def _run_sync(self):
        self.title = '⟳'
        self.menu['⏹  Stop Sync'].set_callback(self._stop_sync)

        self._ensure_progress_win()
        self._progress_win.clear()
        self._progress_win.show()

        def worker():
            try:
                env = {**os.environ, 'TERM': 'dumb', 'NO_COLOR': '1'}
                self._proc = subprocess.Popen(
                    ['bash', SYNC_SCRIPT],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    bufsize=1,
                    text=True,
                    cwd=SCRIPT_DIR,
                    env=env,
                )
                # Answer "y" to "Use previous settings?" prompt
                try:
                    self._proc.stdin.write('y\n')
                    self._proc.stdin.flush()
                    self._proc.stdin.close()
                except OSError:
                    pass

                # Stream output, handle \r (rclone progress overwrites lines)
                buf = ''
                for raw in iter(self._proc.stdout.readline, ''):
                    raw = strip_ansi(raw)
                    for ch in raw:
                        if ch == '\r':
                            buf = ''          # overwrite — discard partial line
                        elif ch == '\n':
                            if buf.strip():
                                style = 'error' if ('ERROR' in buf or 'CRITICAL' in buf) else 'normal'
                                self._progress_win.append(buf, style)
                            buf = ''
                        else:
                            buf += ch
                if buf.strip():
                    self._progress_win.append(buf)

                self._proc.wait()
                code = self._proc.returncode

            except Exception as exc:
                code = -1
                self._progress_win.append(f'[exception] {exc}', 'error')

            self._on_sync_done(code)

        threading.Thread(target=worker, daemon=True).start()

    def _stop_sync(self, _=None):
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
        self._on_sync_done(-2)

    def _on_sync_done(self, code: int):
        def _ui():
            self.menu['⏹  Stop Sync'].set_callback(None)
            if code == 0:
                self.title = '✅'
                self._progress_win.append('', 'dim')
                self._progress_win.append('─── Sync finished successfully ───', 'dim')
                rumps.notification('OneDrive Sync', 'Done', 'Sync completed successfully.')
            elif code == -2:
                self.title = '⛔'
                self._progress_win.append('─── Stopped by user ───', 'dim')
            else:
                self.title = '❌'
                self._progress_win.append(f'─── Exited with code {code} ───', 'error')
                rumps.notification(
                    'OneDrive Sync', 'Error',
                    f'Sync failed (exit {code}). See progress window.'
                )

        run_on_main(_ui)

    def _ensure_progress_win(self):
        if self._progress_win is None:
            try:
                self._progress_win = ProgressWindow()
            except Exception as exc:
                rumps.alert(f'Could not create progress window: {exc}')


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    OneDriveSyncApp().run()
