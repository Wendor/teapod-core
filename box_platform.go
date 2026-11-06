// Adapted from sing-box v1.14.4 experimental/libbox/config.go (platformInterfaceStub, interfaceMonitorStub).
// SPDX-License-Identifier: GPL-3.0-or-later

package teapodcore

import (
	"context"
	"net/netip"
	"os"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/dns"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
)

// boxPlatform — platform interface без возможностей платформы: sing-box работает
// за tun2socks (без TUN-inbound), сокеты приложения исключены из VPN самим сервисом.

type boxPlatform struct{}

func (s *boxPlatform) Initialize(networkManager adapter.NetworkManager) error {
	return nil
}

func (s *boxPlatform) UsePlatformAutoDetectInterfaceControl() bool {
	return true
}

func (s *boxPlatform) AutoDetectInterfaceControl(fd int) error {
	return nil
}

func (s *boxPlatform) UsePlatformInterface() bool {
	return false
}

func (s *boxPlatform) OpenInterface(options *tun.Options, platformOptions option.TunPlatformOptions) (tun.Tun, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) ProcessPlatformOptions(options option.TunPlatformOptions) error {
	return nil
}

func (s *boxPlatform) UsePlatformDefaultInterfaceMonitor() bool {
	return true
}

func (s *boxPlatform) CreateDefaultInterfaceMonitor(logger logger.Logger) tun.DefaultInterfaceMonitor {
	return (*boxInterfaceMonitor)(nil)
}

func (s *boxPlatform) UsePlatformNetworkInterfaces() bool {
	return false
}

func (s *boxPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) UnderNetworkExtension() bool {
	return false
}

func (s *boxPlatform) NetworkExtensionIncludeAllNetworks() bool {
	return false
}

func (s *boxPlatform) ClearDNSCache() {
}

func (s *boxPlatform) RequestPermissionForWIFIState() error {
	return nil
}

func (s *boxPlatform) UsePlatformWIFIMonitor() bool {
	return false
}

func (s *boxPlatform) ReadWIFIState(ctx context.Context) adapter.WIFIState {
	return adapter.WIFIState{}
}

func (s *boxPlatform) UsePlatformConnectionOwnerFinder() bool {
	return false
}

func (s *boxPlatform) FindConnectionOwner(request *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) UsePlatformNotification() bool {
	return false
}

func (s *boxPlatform) SendNotification(notification *adapter.Notification) error {
	return nil
}

func (s *boxPlatform) CancelNotification(identifier string, typeID int32) error {
	return nil
}

func (s *boxPlatform) MyInterfaceAddress() []netip.Addr {
	return nil
}

func (s *boxPlatform) UsePlatformNeighborResolver() bool {
	return false
}

func (s *boxPlatform) StartNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return os.ErrInvalid
}

func (s *boxPlatform) CloseNeighborMonitor(listener adapter.NeighborUpdateListener) error {
	return nil
}

func (s *boxPlatform) UsePlatformShell() bool {
	return false
}

func (s *boxPlatform) CheckPlatformShell() error {
	return nil
}

func (s *boxPlatform) OpenShellSession(user *adapter.PlatformUser, command string, env []string, term string, rows int32, cols int32) (adapter.ShellSession, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) LookupSFTPServer() (string, error) {
	return "", os.ErrInvalid
}

func (s *boxPlatform) ReadSystemSSHHostKey() ([]byte, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) TailscaleHostname() string {
	return ""
}

func (s *boxPlatform) UsePlatformBridge() bool {
	return false
}

func (s *boxPlatform) CreateBridge(options adapter.BridgeOptions) (adapter.BridgeSession, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) LookupUser(username string) (*adapter.PlatformUser, error) {
	return nil, os.ErrInvalid
}

func (s *boxPlatform) UsePlatformLocalDNSTransport() bool {
	return false
}

func (s *boxPlatform) LocalDNSTransport() dns.TransportConstructorFunc[option.LocalDNSServerOptions] {
	return nil
}

type boxInterfaceMonitor struct{}

func (s *boxInterfaceMonitor) Start() error {
	// Монитор без событий: смену сети обрабатывает сервис полным реконнектом.
	return nil
}

func (s *boxInterfaceMonitor) Close() error {
	return nil
}

func (s *boxInterfaceMonitor) DefaultInterface() *control.Interface {
	return nil
}

func (s *boxInterfaceMonitor) OverrideAndroidVPN() bool {
	return false
}

func (s *boxInterfaceMonitor) AndroidVPNEnabled() bool {
	return false
}

func (s *boxInterfaceMonitor) RegisterCallback(callback tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	return nil
}

func (s *boxInterfaceMonitor) UnregisterCallback(element *list.Element[tun.DefaultInterfaceUpdateCallback]) {
}

func (s *boxInterfaceMonitor) RegisterMyInterface(interfaceName string) {
}

func (s *boxInterfaceMonitor) MyInterfaces() []string {
	return nil
}
