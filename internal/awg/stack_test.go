//go:build with_gvisor

package awg

import (
	"net/netip"
	"testing"
	"time"
)

// Читатель TUN, заблокированный в Read до IpcSet, должен проснуться и пересчитать
// смещение под S4 — иначе первый пакет уйдёт без паддинга.
func TestStackDeviceReconfiguredWakesRead(t *testing.T) {
	dev, err := newStackDevice(1408, []netip.Prefix{netip.MustParsePrefix("10.66.0.2/32")})
	if err != nil {
		t.Fatal(err)
	}
	defer dev.Close()
	type result struct {
		n   int
		err error
	}
	done := make(chan result, 1)
	go func() {
		n, err := dev.Read([][]byte{make([]byte, 2048)}, []int{0}, 16)
		done <- result{n, err}
	}()
	time.Sleep(50 * time.Millisecond)
	dev.Reconfigured()
	select {
	case r := <-done:
		if r.n != 0 || r.err != nil {
			t.Fatalf("Read = %d, %v; want 0, nil", r.n, r.err)
		}
	case <-time.After(time.Second):
		t.Fatal("Read not woken by Reconfigured")
	}
}
