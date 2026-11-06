//go:build with_gvisor

package teapodcore

import (
	"context"
	"os"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing/service"
	"github.com/sagernet/sing/service/filemanager"

	"github.com/Wendor/teapod-core/internal/awg"
	"github.com/Wendor/teapod-core/internal/sysdns"
)

// newBoxContext — реестры sing-box с endpoint'ом awg и platform interface без TUN.
// Относительные пути sing-box (cache.db) — в dataDir: cwd процесса на Android — «/», read-only.
func newBoxContext(ctx context.Context, dataDir string) context.Context {
	endpoints := include.EndpointRegistry()
	awg.RegisterEndpoint(endpoints)
	dnsTransports := include.DNSTransportRegistry()
	sysdns.Register(dnsTransports)
	ctx = box.Context(ctx, include.InboundRegistry(), include.OutboundRegistry(), endpoints,
		dnsTransports, include.ServiceRegistry(), include.CertificateProviderRegistry())
	ctx = filemanager.WithDefault(ctx, dataDir, dataDir, os.Getuid(), os.Getgid())
	return service.ContextWith[adapter.PlatformInterface](ctx, (*boxPlatform)(nil))
}
