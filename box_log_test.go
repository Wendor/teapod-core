package teapodcore

import (
	"testing"

	boxlog "github.com/sagernet/sing-box/log"
)

// Форматтер платформы sing-box 1.14 всегда красит вывод (log.disable_color на него не
// действует) — в logcat и vpn_log.txt escape-коды не нужны.
func TestBoxLogLineStripsColors(t *testing.T) {
	got := boxLogLine(boxlog.LevelDebug, "\x1b[37mDEBUG\x1b[0m[0003] [\x1b[38;5;231m3995781847\x1b[0m 0ms] router: ok\n")
	if want := "[Info] DEBUG[0003] [3995781847 0ms] router: ok"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	if got := boxLogLine(boxlog.LevelError, "x"); got != "[Error] x" {
		t.Fatalf("error level: %q", got)
	}
	if got := boxLogLine(boxlog.LevelWarn, "x"); got != "[Warning] x" {
		t.Fatalf("warn level: %q", got)
	}
}
